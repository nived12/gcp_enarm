# Turns what a provider says about a person into the account they sign in to: the one
# already linked to them, an existing account with the same email (linked now), or a new
# one. Returns { user:, outcome: } with outcome :returning, :linked or :created.
#
# An email is only trusted when the provider says it verified it. Linking on an
# unverified address would hand an existing account to whoever typed that address into
# a Google account; creating on one would squat the address before its owner signs up.
module Identities
  class Resolver < ApplicationService
    def initialize(auth:, time_zone: nil)
      super()
      @auth = auth
      @time_zone = time_zone
    end

    def call
      identity = Identity.find_by(provider: auth.provider, uid: auth.uid)
      return returning(identity) if identity

      existing = email && User.find_by(email: email)
      return failure(I18n.t("identities.unverified.#{existing ? "link" : "create"}")) unless verified?
      return link(existing) if existing

      create
    end

    def context_for_logging
      { provider: auth.provider, uid: auth.uid }
    end

    private

    attr_reader :auth, :time_zone

    def returning(identity)
      identity.update!(email: email || identity.email)
      success(user: identity.user, outcome: :returning)
    end

    # The account already carries a different Google identity: the person changed the
    # address on the Google account they first linked, and this is another one.
    def link(user)
      return failure(I18n.t("identities.already_linked")) if user.identities.exists?(provider: auth.provider)

      user.identities.create!(provider: auth.provider, uid: auth.uid, email: email)
      success(user: user, outcome: :linked)
    end

    def create
      user = User.transaction do
        User.create!(new_user_attributes).tap do |created|
          created.identities.create!(provider: auth.provider, uid: auth.uid, email: email)
        end
      end
      success(user: user, outcome: :created)
    end

    # Google splits the profile name the way the person entered it; a profile with no
    # given name falls back to the display name, then to the address itself.
    def new_user_attributes
      first_name = info["first_name"].presence || info["name"].presence || email.split("@").first
      { email: email, first_name: first_name.to_s.first(100), last_name: info["last_name"].to_s.first(100).presence,
        time_zone: (time_zone if User::TIME_ZONES.include?(time_zone)) }.compact
    end

    def info
      auth.info
    end

    # The Google strategy leaves `email` out unless verified and keeps the raw address in
    # `unverified_email`; `email_verified` arrives as a boolean or, from older endpoints,
    # the string "true".
    def email
      (info["email"].presence || info["unverified_email"]).to_s.strip.downcase.presence
    end

    def verified?
      email.present? && ActiveModel::Type::Boolean.new.cast(info["email_verified"]) == true
    end
  end
end

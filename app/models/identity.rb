# A way to sign in that is not a password: the provider's stable id for the person, tied
# to one account. One per provider per account.
class Identity < ApplicationRecord
  # Values are OmniAuth's strategy names, which is what the callback reports.
  enum :provider, { google: "google_oauth2" }, prefix: :provider

  belongs_to :user

  validates :uid, presence: true, uniqueness: { scope: :provider }
  validates :user_id, uniqueness: { scope: :provider }

  # The button is shown, and the request phase lets a student through, only when both
  # credentials are set. Read per request so the specs can switch it; in production the
  # middleware took the same values at boot.
  def self.google_available?
    ENV["GOOGLE_CLIENT_ID"].present? && ENV["GOOGLE_CLIENT_SECRET"].present?
  end
end

# Which button brought a new account, for the signed_up event. Each sign-up link names
# itself with ?from=; the value waits in the session, the way return_to does, so it
# survives the round trip through Google as well as a form that has to be sent twice.
# Only the names below are kept: the parameter is in the address bar, and anything else
# would reach PostHog verbatim.
module SignUpTracking
  extend ActiveSupport::Concern

  SOURCES = %w[header hero case pricing closing pricing_page sign_in].freeze

  private

  def remember_sign_up_source
    source = params[:from].presence_in(SOURCES)
    session[:sign_up_source] = source if source
  end

  # $set_once files the method and source on the person, so every later event can be
  # broken down by how the student arrived without sending them again.
  def track_sign_up(user, method)
    source = session.delete(:sign_up_source) || "direct"
    Analytics.capture(
      user, "signed_up",
      method: method, source: source, "$set_once": { sign_up_method: method, sign_up_source: source }
    )
  end
end

# Where a provider sends the student back. The sign-in rules live in Identities::Resolver;
# this only starts the session and says what happened.
class OmniauthCallbacksController < ApplicationController
  allow_unauthenticated_access
  allow_unverified_email

  def create
    result = Identities::Resolver.call(
      auth: request.env.fetch("omniauth.auth"), time_zone: request.env.fetch("omniauth.params", {})["time_zone"]
    )
    return redirect_to(new_session_path, alert: result.errors.full_messages.to_sentence) if result.failure?

    start_new_session_for(result.payload[:user])
    redirect_to after_authentication_url, notice: t("identities.outcomes.#{result.payload[:outcome]}")
  end

  # Google sends ?error=access_denied when the student closes the consent screen, which
  # OmniAuth passes on as the message. Anything else is ours or Google's to fix.
  def failure
    reason = params[:message] == "access_denied" ? "cancelled" : "failed"
    redirect_to new_session_path, alert: t("identities.failure.#{reason}")
  end
end

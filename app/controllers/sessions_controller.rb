class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  allow_unverified_email

  rate_limit to: 10, within: 3.minutes, only: :create, with: -> {
    redirect_to new_session_path, alert: t("sessions.create.rate_limited")
  }

  def new
    remember_return_to
  end

  def create
    user = User.authenticate_by(params.permit(:email, :password))

    if user
      start_new_session_for(user)
      # Straight to the waiting page, so a return_to survives until the address is proven.
      redirect_to user.email_verified? ? after_authentication_url : email_verification_path
    else
      redirect_to new_session_path, alert: t("sessions.create.invalid")
    end
  end

  def destroy
    terminate_session
    redirect_to root_path, status: :see_other, notice: t("sessions.destroy.success")
  end
end

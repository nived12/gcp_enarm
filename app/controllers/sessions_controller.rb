class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]

  rate_limit to: 10, within: 3.minutes, only: :create, with: -> {
    redirect_to new_session_path, alert: t("sessions.create.rate_limited")
  }

  def new
  end

  def create
    user = User.authenticate_by(params.permit(:email, :password))

    if user
      start_new_session_for(user)
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: t("sessions.create.invalid")
    end
  end

  def destroy
    terminate_session
    redirect_to root_path, status: :see_other, notice: t("sessions.destroy.success")
  end
end

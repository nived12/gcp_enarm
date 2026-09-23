class RegistrationsController < ApplicationController
  allow_unauthenticated_access

  rate_limit to: 10, within: 10.minutes, only: :create, with: -> {
    redirect_to new_registration_path, alert: t("sessions.create.rate_limited")
  }

  def new
    remember_return_to
    @user = User.new
  end

  def create
    @user = User.new(registration_params)

    if @user.save
      start_new_session_for(@user)
      redirect_to after_authentication_url, notice: t("registrations.create.welcome")
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  def registration_params
    params.expect(user: [:name, :email, :password, :password_confirmation])
  end
end

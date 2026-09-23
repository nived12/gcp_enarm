class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  allow_unverified_email

  rate_limit to: 10, within: 10.minutes, only: :create, with: -> {
    redirect_to new_registration_path, alert: t("sessions.create.rate_limited")
  }

  def new
    remember_return_to
    @user = User.new
  end

  def create
    @user = User.new(registration_params)

    if @user.save(context: :sign_up)
      EmailVerificationsMailer.verify(@user).deliver_later
      start_new_session_for(@user)
      redirect_to email_verification_path
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  # The time zone is what the browser reports, not something the student typed, so one it
  # could not name, or named in a way tzinfo does not know, leaves the default rather than
  # refusing the account. It can be changed on /account.
  def registration_params
    params.expect(
      user: [:first_name, :last_name, :email, :password, :password_confirmation,
      :time_zone]
    ).tap do |attributes|
      attributes.delete(:time_zone) unless User::TIME_ZONES.include?(attributes[:time_zone])
    end
  end
end

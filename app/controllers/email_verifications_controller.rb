# The page a new account waits on until its address is proven, the resend button on it,
# and where the link in the email lands. The link works signed out too: it is often
# opened on the phone while the account was made on a laptop.
class EmailVerificationsController < ApplicationController
  allow_unauthenticated_access only: :confirm
  allow_unverified_email
  before_action :leave_if_verified, only: %i[show create]

  rate_limit to: 3, within: 10.minutes, only: :create, with: -> {
    redirect_to email_verification_path, alert: t("sessions.create.rate_limited")
  }

  def show
  end

  def create
    EmailVerificationsMailer.verify(Current.user).deliver_later
    redirect_to email_verification_path, notice: t("email_verifications.create.sent")
  end

  def confirm
    user = User.find_by_token_for(:email_verification, params[:token])
    unless user
      back = authenticated? ? email_verification_path : new_session_path
      return redirect_to(back, alert: t("email_verifications.confirm.invalid"))
    end

    user.verify_email!
    if authenticated? && Current.user == user
      redirect_to after_authentication_url, notice: t("email_verifications.confirm.verified")
    else
      redirect_to new_session_path, notice: t("email_verifications.confirm.verified_sign_in")
    end
  end

  private

  def leave_if_verified
    redirect_to root_path if Current.user.email_verified?
  end
end

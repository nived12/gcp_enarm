class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[edit update]

  rate_limit to: 10, within: 3.minutes, only: :create, with: -> {
    redirect_to new_password_path, alert: t("sessions.create.rate_limited")
  }

  def new
  end

  def create
    user = User.find_by(email: params[:email])
    PasswordsMailer.reset(user).deliver_later if user

    # Always the same message: a different response for a known address turns this
    # form into an account-enumeration oracle.
    redirect_to new_session_path, notice: t("passwords.create.sent")
  end

  def edit
  end

  def update
    if @user.update(params.permit(:password, :password_confirmation))
      @user.sessions.destroy_all
      redirect_to new_session_path, notice: t("passwords.update.success")
    else
      redirect_to edit_password_path(params[:token]), alert: @user.errors.full_messages.to_sentence
    end
  end

  private

  def set_user_by_token
    @user = User.find_by_password_reset_token!(params[:token])
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    redirect_to new_password_path, alert: t("passwords.update.invalid_token")
  end
end

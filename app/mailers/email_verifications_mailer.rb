class EmailVerificationsMailer < ApplicationMailer
  def verify(user)
    @user = user
    # One token for both parts: each call signs its own expiry, so two would differ.
    @token = user.generate_token_for(:email_verification)
    mail subject: t("email_verifications_mailer.verify.subject"),
      to: email_address_with_name(user.email, user.full_name)
  end
end

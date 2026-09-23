class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    mail subject: t("passwords_mailer.reset.subject"), to: email_address_with_name(user.email, user.full_name)
  end
end

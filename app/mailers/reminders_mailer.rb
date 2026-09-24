class RemindersMailer < ApplicationMailer
  # `message` is ReminderMessage#to_h, built when the reminder was claimed, so this email
  # says exactly what the push notification sent alongside it says.
  def reminder(user, message)
    @user = user
    @message = message
    @url = URI.join(root_url, message[:path]).to_s
    @unsubscribe_url = reminder_unsubscribe_url(user.generate_token_for(:reminder_unsubscribe))

    # RFC 8058: mail clients show their own "unsubscribe" button and POST to this URL
    # without opening it, and Gmail and Yahoo require it of anyone sending in bulk.
    headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"

    mail subject: message[:title], to: email_address_with_name(user.email, user.full_name)
  end
end

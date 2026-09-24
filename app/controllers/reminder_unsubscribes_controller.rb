# The unsubscribe link at the foot of every reminder email. It works signed out, from any
# device, for as long as the email exists.
#
# Opening the link only asks; the button POSTs. Mail scanners and link previewers fetch
# every URL in a message, and a GET that unsubscribed would turn reminders off for
# students who never clicked. The POST is also what a mail client's own "unsubscribe"
# button sends (List-Unsubscribe-Post, RFC 8058), without a session or a CSRF token.
class ReminderUnsubscribesController < ApplicationController
  allow_unauthenticated_access
  allow_unverified_email
  skip_forgery_protection only: :create

  before_action :set_user

  def show
  end

  def create
    @user.reminder_settings.update!(by_email: false)
    render :done
  end

  private

  def set_user
    @user = User.find_by_token_for(:reminder_unsubscribe, params[:token])
    render :invalid, status: :not_found unless @user
  end
end

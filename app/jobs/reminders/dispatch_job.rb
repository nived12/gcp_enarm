# Sends every reminder that is due. Scheduled every 15 minutes in config/recurring.yml;
# each student's own time zone decides what "due" means, and ReminderDelivery makes a
# repeated or overlapping run harmless.
module Reminders
  class DispatchJob < ApplicationJob
    queue_as :default

    def perform(now: Time.current)
      ReminderPreference.wanting_any.includes(:user).find_each do |preference|
        next unless preference.user.email_verified?

        # One student's bad data must not cost everyone after them their reminder.
        Rails.error.handle(context: { user_id: preference.user_id }) do
          Dispatcher.call(user: preference.user, now: now)
        end
      end
    end
  end
end

# The reminder section of /account: which reminders, at what time, and whether by email.
# Push is switched on per device by PushSubscriptionsController, not here.
class ReminderPreferencesController < ApplicationController
  def update
    preference = Current.user.reminder_settings
    unless preference.update(preference_params)
      return redirect_to(
        account_path(anchor: "reminders"), alert: t("reminders.preferences.invalid"),
        status: :see_other
      )
    end

    redirect_to account_path(anchor: "reminders"), notice: saved_notice(preference), status: :see_other
  end

  private

  def preference_params
    params.expect(reminder_preference: %i[study_days streak_at_risk exam_countdown by_email minute_of_day])
  end

  # Reminders with nowhere to go are a setting that silently does nothing; say so.
  def saved_notice(preference)
    deliverable = preference.by_email || (PushSubscription.enabled? && Current.user.push_subscriptions.exists?)
    return t("reminders.preferences.saved_without_channel") if preference.any_reminder? && !deliverable

    t("reminders.preferences.saved")
  end
end

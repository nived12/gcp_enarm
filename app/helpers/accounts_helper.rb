module AccountsHelper
  # Each zone with the time it is there now, which is how a student recognises their own.
  # A zone the browser gave at sign-up that is not among the choices is kept as one more,
  # so saving the form never moves them without asking.
  def time_zone_options(user, now: Time.current)
    zones = User::TIME_ZONE_CHOICES.values
    zones += [user.time_zone] unless zones.include?(user.time_zone)
    zones.map do |zone|
      [t("time_zones.option", name: zone_name(zone), time: now.in_time_zone(zone).strftime("%H:%M")), zone]
    end
  end

  def time_zone_name(user)
    zone_name(user.time_zone)
  end

  def reminder_time_options
    ReminderPreference::MINUTE_CHOICES.map { |minute| [clock_time(minute), minute] }
  end

  # "08:00" for 480 minutes after midnight, on the 24-hour clock schedules in Mexico use.
  def clock_time(minute)
    format("%02d:%02d", *minute.divmod(60))
  end

  private

  def zone_name(zone)
    key = User::TIME_ZONE_CHOICES.key(zone)
    key ? t("time_zones.names.#{key}") : zone.split("/").last.tr("_", " ")
  end
end

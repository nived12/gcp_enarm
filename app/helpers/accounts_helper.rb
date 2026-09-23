module AccountsHelper
  # Each zone with the time it is there now, which is how a student recognises their own.
  # A zone the browser gave at sign-up that is not among the choices is kept as one more,
  # so saving the form never moves them without asking.
  def time_zone_options(user, now: Time.current)
    choices = User::TIME_ZONE_CHOICES.map { |key, zone| [t("time_zones.names.#{key}"), zone] }
    unless User::TIME_ZONE_CHOICES.value?(user.time_zone)
      choices << [user.time_zone.split("/").last.tr("_", " "), user.time_zone]
    end
    choices.map do |name, zone|
      [t("time_zones.option", name: name, time: now.in_time_zone(zone).strftime("%H:%M")), zone]
    end
  end
end

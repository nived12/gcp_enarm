module StudyPlansHelper
  # What a day is about, in one line: its topics, or what kind of day it is.
  def plan_day_title(day)
    return day.topics.map(&:name).join(" · ") if day.kind_topics?
    return t("study_plans.kinds.case_workshop_of", specialty: day.specialty.name) if day.kind_case_workshop?

    t("study_plans.kinds.#{day.kind}")
  end

  # The specialty's colour for the day, or none: reviews, simulacros and catch-up days
  # belong to no specialty.
  def plan_day_color_class(day)
    day.specialty ? "specialty-#{day.specialty.color_token}" : "specialty-none"
  end

  def plan_date(date, format = :day)
    l(date, format: t("study_plans.date_formats.#{format}"))
  end
end

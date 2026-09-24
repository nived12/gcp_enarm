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

  # "5 – 11 de octubre", or "28 de septiembre – 4 de octubre" when the week straddles two.
  def plan_week_range(week)
    first, last = week.first, week.last
    if first.month == last.month
      t(
        "study_plans.show.week_range.same_month", first_day: first.day, last_day: last.day,
        month: l(first, format: "%B")
      )
    else
      t("study_plans.show.week_range.two_months", from: plan_date(first), to: plan_date(last))
    end
  end

  # Where a day stands, for the calendar to say so: done, a quiz left half-way, or gone
  # by without being done. A catch-up day that passed is slack spent, not a debt.
  def plan_day_status(day, today)
    return :done if day.done?
    return :in_progress if day.exam&.unfinished?

    :missed if day.date < today && !day.kind_catch_up?
  end

  # Whether a day brings a quiz and how long, or is for reading. Asks the bank, so it is
  # for the seven days of a week rather than a whole month.
  def plan_day_workload(day)
    return if day.kind_catch_up?
    return t("study_plans.show.reading") unless day.quiz?

    t("study_plans.show.#{day.kind_topics? ? "quiz" : "questions"}", count: day.question_count)
  end

  def remembered_calendar_view
    StudyPlansController::CALENDAR_VIEWS.include?(cookies[:calendar_view]) ? cookies[:calendar_view] : "week"
  end

  # The calendar at `date`, in the given view or the one the student last chose.
  def study_calendar_path(date, view = remembered_calendar_view)
    return study_plan_path(week: date.beginning_of_week(:monday).iso8601) if view == "week"

    study_plan_path(month: date.strftime("%Y-%m"))
  end
end

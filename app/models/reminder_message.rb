# The words of one reminder, built once and sent unchanged to every channel, so a
# notification and its email never disagree. Kinds arrive in the order they should be
# read: a countdown first, then the day's own message.
class ReminderMessage
  attr_reader :kinds, :date, :plan, :plan_day, :streak

  def initialize(kinds:, date:, plan: nil, plan_day: nil, streak: nil)
    @kinds = kinds
    @date = date
    @plan = plan
    @plan_day = plan_day
    @streak = streak
  end

  def title
    title_for(kinds.first)
  end

  def lines
    kinds.flat_map { |kind| lines_for(kind) }
  end

  # Where tapping the notification or the email's button lands.
  def path
    case kinds.last
    when "study_day" then routes.study_plan_day_path(date)
    when "streak_at_risk" then routes.root_path
    else routes.study_plan_path
    end
  end

  def to_h
    { title: title, lines: lines, path: path }
  end

  private

  def title_for(kind)
    case kind
    when "exam_countdown" then I18n.t("reminders.message.exam_countdown.title", count: days_left)
    when "study_day" then I18n.t("reminders.message.study_day.title")
    else I18n.t("reminders.message.streak_at_risk.title", count: streak.current)
    end
  end

  def lines_for(kind)
    case kind
    when "exam_countdown" then [I18n.t("reminders.message.exam_countdown.body.days_#{days_left}")]
    when "study_day" then study_day_lines
    else [I18n.t("reminders.message.streak_at_risk.body", minimum: streak.minimum)]
    end
  end

  def study_day_lines
    lines = [I18n.t("reminders.message.study_day.body", day: helpers.plan_day_title(plan_day))]
    lines << I18n.t("reminders.message.study_day.streak", count: streak.current) if streak.current.positive?
    lines
  end

  def days_left
    (plan.exam_date - date).to_i
  end

  def helpers
    ApplicationController.helpers
  end

  def routes
    Rails.application.routes.url_helpers
  end
end

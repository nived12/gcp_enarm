# One day of the study plan: what it names, and the quiz on exactly that.
class StudyPlanDaysController < ApplicationController
  include UpgradePath

  before_action :set_plan
  before_action :set_day, only: %i[quiz complete]

  def show
    @date = parsed_date
    @day = @plan.day_on(@date)
  end

  # A quiz already started for the day is picked up rather than drawn again, so going
  # back to the day never leaves an orphaned exam behind.
  def quiz
    return redirect_to(exam_path(@day.exam)) if @day.exam&.unfinished?

    request = @day.exam_request
    result = Exams::Builder.call(user: Current.user, mode: request[:mode], filters: request[:filters])
    if result.failure?
      return redirect_to_upgrade(result) if daily_limit_reached?(result)

      return redirect_to(study_plan_day_path(@day.date), alert: result.errors.full_messages.to_sentence)
    end

    exam = result.payload[:exam]
    @day.update!(exam: exam)
    Analytics.capture(Current.user, "exam_started", exam.usage_properties.merge(from_study_plan: true))
    redirect_to exam.feedback_at_end? ? exam_path(exam) : exam_question_path(exam, 1)
  end

  # For a day with nothing to finish: a reading day, a catch-up day.
  def complete
    @day.update!(completed_at: Time.current)
    redirect_to study_plan_day_path(@day.date), notice: t("study_plans.day.completed")
  end

  private

  def set_plan
    @plan = Current.user.study_plan
    redirect_to new_study_plan_path unless @plan
  end

  def set_day
    @day = @plan.days.find_by!(date: parsed_date)
  end

  def parsed_date
    Date.iso8601(params[:date])
  rescue Date::Error
    raise ActiveRecord::RecordNotFound
  end
end

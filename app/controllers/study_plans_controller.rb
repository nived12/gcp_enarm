# The study calendar: creating a plan, the month grid, and moving the plan when the
# student changes the exam date, their week, or falls behind.
class StudyPlansController < ApplicationController
  before_action :set_plan, only: %i[show edit update destroy catch_up]
  before_action :redirect_existing, only: %i[new create]

  def show
    @today = Current.user.study_date
    @month = month_param || @today.beginning_of_month
    @days = @plan.days.where(date: @month.all_month).includes(:specialty, :exam, :topics).index_by(&:date)
    @missed = @plan.missed_days(@today).size
  end

  def new
    @plan = Current.user.build_study_plan(
      exam_date: StudyPlan.default_exam_date(Current.user.study_date), template: "six_days"
    )
  end

  def create
    result = StudyPlans::Builder.call(
      user: Current.user, exam_date: plan_params[:exam_date], template: plan_params[:template]
    )
    return redirect_to(study_plan_path, notice: t("study_plans.create.done")) if result.success?

    @plan = Current.user.build_study_plan(plan_params)
    @error = result.errors.full_messages.to_sentence
    render :new, status: :unprocessable_content
  end

  def edit
  end

  def update
    reschedule(**plan_params.to_h.symbolize_keys) { render :edit, status: :unprocessable_content }
  end

  # Missed days slide forward to today; see StudyPlans::Rescheduler.
  def catch_up
    reschedule { redirect_to study_plan_path, alert: @error }
  end

  def destroy
    @plan.destroy!
    redirect_to new_study_plan_path, notice: t("study_plans.destroy.done"), status: :see_other
  end

  private

  def set_plan
    @plan = Current.user.study_plan
    redirect_to new_study_plan_path unless @plan
  end

  def redirect_existing
    redirect_to study_plan_path if Current.user.study_plan
  end

  def reschedule(**changes)
    result = StudyPlans::Rescheduler.call(plan: @plan, today: Current.user.study_date, **changes)
    return redirect_to(study_plan_path, notice: t("study_plans.update.done")) if result.success?

    @error = result.errors.full_messages.to_sentence
    yield
  end

  # "2027-03" from the month navigation. Anything else falls back to this month.
  def month_param
    Date.strptime(params[:month].to_s, "%Y-%m")
  rescue Date::Error
    nil
  end

  def plan_params
    params.expect(study_plan: %i[exam_date template])
  end
end

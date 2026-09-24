# The study calendar: creating a plan, its week and month views, and moving the plan when
# the student changes the exam date, their week, or falls behind.
class StudyPlansController < ApplicationController
  before_action :set_plan, only: %i[show edit update destroy catch_up]
  before_action :redirect_existing, only: %i[new create]

  CALENDAR_VIEWS = %w[week month].freeze

  # The week is the default: it is what a student checks to know what comes next, and the
  # app reads in one narrow column on every screen, so it is not only a phone's view.
  # Whichever view the student last chose is remembered, so month stays month.
  def show
    @today = Current.user.study_date
    @view = calendar_view
    @period = @view == "week" ? week_shown : month_shown
    @days = @plan.days.where(date: @period).includes(:specialty, :exam, :topics).index_by(&:date)
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
    if result.success?
      track_plan_created(result.payload[:plan])
      return redirect_to(study_plan_path, notice: t("study_plans.create.done"))
    end

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

  # Weeks rather than the date itself: how far ahead students plan is the question, and
  # the date alone would only say which sitting they are aiming at.
  def track_plan_created(plan)
    Analytics.capture(
      Current.user, "study_plan_created",
      template: plan.template, weeks_to_exam: (plan.exam_date - plan.starts_on).to_i / 7
    )
  end

  def reschedule(**changes)
    result = StudyPlans::Rescheduler.call(plan: @plan, today: Current.user.study_date, **changes)
    return redirect_to(study_plan_path, notice: t("study_plans.update.done")) if result.success?

    @error = result.errors.full_messages.to_sentence
    yield
  end

  # A `week` or `month` in the URL names the view as well as the period, and becomes the
  # view the calendar opens in next time.
  def calendar_view
    explicit = CALENDAR_VIEWS.find { |view| params.key?(view) }
    return cookies.permanent[:calendar_view] = explicit if explicit

    helpers.remembered_calendar_view
  end

  # Any date of the week, usually its Monday: weeks start on Monday in Mexico. Anything
  # unreadable falls back to this week.
  def week_shown
    monday = week_date.beginning_of_week(:monday)
    monday..(monday + 6)
  end

  def week_date
    Date.iso8601(params[:week].to_s)
  rescue Date::Error
    @today
  end

  # "2027-03" from the month navigation. Anything else falls back to this month.
  def month_shown
    Date.strptime(params[:month].to_s, "%Y-%m").all_month
  rescue Date::Error
    @today.all_month
  end

  def plan_params
    params.expect(study_plan: %i[exam_date template])
  end
end

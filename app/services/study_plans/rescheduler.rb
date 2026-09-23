# Moves a plan onto new dates without starting it over: after the student falls behind,
# moves the exam or changes which days they rest.
#
# Until a day is done there is nothing to keep, so the plan is simply built again from
# today. After that, done days stay where they happened and everything not done — missed
# days included — slides forward in order onto the study dates left, from today. The
# Fitter decides what gives way when that no longer fits. Restarting the syllabus from
# zero is the failure the prep literature names, so a re-fit never does it.
module StudyPlans
  class Rescheduler < ApplicationService
    def initialize(plan:, today:, exam_date: nil, template: nil)
      super()
      @plan = plan
      @today = today
      @exam_date = exam_date
      @template = template
    end

    def call
      plan.assign_attributes({ exam_date: exam_date, template: template }.compact)
      return rebuild if done.empty?
      return failure(plan.errors.full_messages.to_sentence) unless plan.valid?

      placed = Fitter.fit(pending.map { |day| Slot.from_day(day) }, dates)
      return failure(I18n.t("study_plans.rescheduler.no_room")) unless placed

      StudyPlan.transaction do
        plan.save!
        DayWriter.clear(plan.days.where.not(id: done.map(&:id)))
        DayWriter.write(plan, placed)
      end
      success(plan: plan.reload)
    end

    def context_for_logging
      { study_plan_id: plan.id, exam_date: plan.exam_date, template: plan.template }
    end

    private

    attr_reader :plan, :today, :exam_date, :template

    def rebuild
      Builder.call(user: plan.user, exam_date: plan.exam_date, template: plan.template, today: today)
    end

    def days
      @days ||= plan.days.includes(:exam, :day_topics).to_a
    end

    def done
      @done ||= days.select(&:done?)
    end

    # A catch-up day that has gone by was slack, and it is spent.
    def pending
      days.reject { |day| day.done? || (day.date < today && day.kind_catch_up?) }
    end

    def dates
      plan.study_dates(today) - done.map(&:date)
    end
  end
end

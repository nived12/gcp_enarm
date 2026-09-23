require "rails_helper"

RSpec.describe StudyPlans::Rescheduler do
  let(:user) { create(:user) }
  let(:start) { Date.new(2026, 10, 5) }
  let(:plan) do
    create_syllabus
    StudyPlans::Builder.call(user: user, exam_date: (start + 60).iso8601, template: "every_day", today: start)
                       .payload[:plan]
  end

  def reschedule(today:, **changes)
    described_class.call(plan: StudyPlan.find(plan.id), today: today, **changes)
  end

  def topics_on(day)
    day.day_topics.map(&:topic_id)
  end

  it "builds the plan again from today while nothing is done yet" do
    result = reschedule(today: start + 5)

    expect(result.payload[:plan].starts_on).to eq(start + 5)
    expect(result.payload[:plan].days.first.date).to eq(start + 5)
  end

  it "keeps done days and slides everything missed forward to today, in order" do
    days = plan.days.includes(:day_topics).to_a
    days.first.update!(completed_at: Time.current)
    missed = days.second
    third = days.third

    result = reschedule(today: start + 3)
    moved = result.payload[:plan].days.includes(:day_topics).to_a

    expect(moved.first).to eq(days.first)
    expect(moved.second.date).to eq(start + 3)
    expect(topics_on(moved.second)).to eq(topics_on(missed))
    expect(topics_on(moved.third)).to eq(topics_on(third))
    expect(moved.last).to be_kind_assessment
    expect(moved.last.date).to eq(start + 59)
    expect(moved.flat_map { |day| topics_on(day) }).to match_array(days.flat_map { |day| topics_on(day) })
  end

  it "keeps a quiz started on a missed day with its topics" do
    exam = create(:exam, user: user)
    days = plan.days.to_a
    days.first.update!(completed_at: Time.current)
    days.second.update!(exam: exam)

    moved = reschedule(today: start + 3).payload[:plan].days.to_a

    expect(moved.second).to have_attributes(date: start + 3, exam: exam)
  end

  it "spends the catch-up days that have gone by" do
    days = plan.days.to_a
    catch_up = days.find(&:kind_catch_up?)
    days.take_while { |day| day != catch_up }.each { |day| day.update!(completed_at: Time.current) }

    moved = reschedule(today: catch_up.date + 1).payload[:plan].days.to_a

    expect(moved).not_to include(catch_up)
    expect(moved.count(&:kind_catch_up?)).to eq(days.count(&:kind_catch_up?) - 1)
    expect(moved.map(&:date)).to eq(days.map(&:date) - [catch_up.date])
  end

  it "moves the rest of the plan to a new exam date and week" do
    plan.days.first.update!(completed_at: Time.current)

    result = reschedule(today: start + 1, exam_date: (start + 90).iso8601, template: "six_days")
    moved = result.payload[:plan].days.to_a

    expect(result.payload[:plan]).to have_attributes(exam_date: start + 90, template: "six_days", starts_on: start)
    expect(moved.last.date).to eq(start + 89)
    expect(moved.drop(1).map { |day| day.date.wday }).not_to include(0)
  end

  it "fills the days after a finished syllabus with review, up to the simulacro" do
    days = plan.days.to_a
    days[0...-1].each { |day| day.update!(completed_at: Time.current) }

    moved = reschedule(today: start + 1, exam_date: (start + 65).iso8601).payload[:plan].days.to_a

    expect(moved.last(6).map(&:kind)).to eq(%w[review] * 5 + %w[assessment])
    expect(moved.last.date).to eq(start + 64)
  end

  it "has nothing to move once every day is done" do
    plan.days.update_all(completed_at: Time.current)

    expect { reschedule(today: start + 3) }.not_to(change { plan.days.pluck(:id, :date) })
  end

  it "says so when there is no study day left before the exam" do
    plan.days.first.update!(completed_at: Time.current)

    result = reschedule(today: start + 60)

    expect(result.errors.full_messages).to eq([I18n.t("study_plans.rescheduler.no_room")])
  end

  it "refuses an impossible date without touching the plan" do
    plan.days.first.update!(completed_at: Time.current)

    result = reschedule(today: start + 1, exam_date: "")

    expect(result.errors.full_messages).to eq([I18n.t("study_plans.errors.exam_date_missing")])
    expect(plan.reload.exam_date).to eq(start + 60)
  end
end

require "rails_helper"

RSpec.describe StudyPlans::Builder do
  let(:user) { create(:user) }
  let(:today) { Date.new(2026, 10, 5) } # a Monday
  let!(:syllabus) { create_syllabus }

  def build(days:, template: "every_day", on: today)
    described_class.call(user: user, exam_date: (on + days).iso8601, template: template, today: on)
  end

  def plan_days(result)
    result.payload[:plan].days.includes(:day_topics, :specialty).to_a
  end

  def topic_ids_in(days)
    days.select(&:kind_topics?).flat_map { |day| day.day_topics.map(&:topic_id) }
  end

  it "fills every study day from today to the eve of the exam, ending in a simulacro" do
    days = plan_days(build(days: 100))

    expect(days.map(&:date)).to eq((today...(today + 100)).to_a)
    expect(days.last).to be_kind_assessment
    expect(days.first).to be_kind_topics
  end

  it "walks every topic in every pass, surgery first, branch by branch" do
    days = plan_days(build(days: 100))

    expect(days.map(&:pass_number).uniq).to eq([1, 2, 3])
    all_topics = syllabus.values.flatten.map(&:id)
    days.group_by(&:pass_number).each_value do |pass|
      expect(topic_ids_in(pass)).to match_array(all_topics)
    end

    walk = syllabus.values_at("cirugia-general", "gineco-obstetricia", "pediatria", "medicina-interna", "urgencias")
    expect(topic_ids_in(days.select { |day| day.pass_number == 1 })).to eq(walk.flatten.map(&:id))
    expect(days.select(&:kind_topics?)).to all(satisfy { |day| day.day_topics.any? })
  end

  it "closes each specialty with a workshop and slack, and each pass with a review and a simulacro" do
    days = plan_days(build(days: 100))
    first_pass = days.select { |day| day.pass_number == 1 }
    last_pass = days.select { |day| day.pass_number == 3 }

    expect(first_pass.count(&:kind_case_workshop?)).to eq(5)
    expect(first_pass.count(&:kind_catch_up?)).to eq(5)
    expect(last_pass.count(&:kind_catch_up?)).to eq(0)
    expect(first_pass.last(2).map(&:kind)).to eq(%w[review assessment])
    expect(first_pass.find(&:kind_case_workshop?).specialty.slug).to eq("cirugia-general")
  end

  it "gets faster pass after pass" do
    days = plan_days(build(days: 100)).select(&:kind_topics?)
    load = days.group_by(&:pass_number).transform_values do |pass|
      pass.sum { |day| day.day_topics.size }.fdiv(pass.size)
    end

    expect(load[1]).to be < load[2]
    expect(load[2]).to be < load[3]
  end

  it "drops a pass rather than overload a day when there is less time" do
    expect(plan_days(build(days: 45)).map(&:pass_number).uniq).to eq([1, 2])
    expect(plan_days(build(days: 21)).map(&:pass_number).uniq).to eq([1])
  end

  it "leaves rest days empty" do
    days = plan_days(build(days: 60, template: "five_days"))

    expect(days.map { |day| day.date.wday }).not_to include(0, 6)
    expect(days.first.date).to eq(today)
  end

  it "starts on the next study day when today is a rest day" do
    sunday = Date.new(2026, 10, 4)

    expect(plan_days(build(days: 60, template: "six_days", on: sunday)).first.date).to eq(today)
  end

  it "gives a long plan one topic a day and spends the rest on review" do
    days = plan_days(build(days: 700))
    first_pass = days.select { |day| day.pass_number == 1 }

    expect(first_pass.select(&:kind_topics?).map { |day| day.day_topics.size }.uniq).to eq([1])
    expect(first_pass.count(&:kind_review?)).to be > 100
  end

  it "replaces the student's plan rather than keeping two" do
    first = build(days: 60).payload[:plan]
    second = build(days: 90).payload[:plan]

    expect(second).to eq(first)
    expect(second.days.maximum(:date)).to eq(today + 89)
    expect(StudyPlan.count).to eq(1)
  end

  it "refuses an exam date too close, too far or missing, with the reason" do
    expect(build(days: 10).errors.full_messages).to eq([I18n.t("study_plans.errors.exam_date_too_close", minimum: 21)])
    expect(build(days: 800).errors.full_messages).to eq([I18n.t("study_plans.errors.exam_date_too_far")])
    missing = described_class.call(user: user, exam_date: "", template: "every_day", today: today)
    expect(missing.errors.full_messages).to eq([I18n.t("study_plans.errors.exam_date_missing")])
    expect(StudyPlan.count).to eq(0)
  end

  it "has nothing to build from an empty syllabus" do
    StudyPlanDayTopic.delete_all
    Topic.delete_all

    expect(build(days: 60).errors.full_messages).to eq([I18n.t("study_plans.builder.no_topics")])
  end

  it "defaults today to the student's own study day" do
    travel_to Time.zone.local(2026, 10, 5, 12) do
      result = described_class.call(user: user, exam_date: "2027-09-28", template: "six_days")

      expect(result.payload[:plan].starts_on).to eq(user.study_date)
    end
  end
end

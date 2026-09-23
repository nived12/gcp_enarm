require "rails_helper"

RSpec.describe StudyPlan do
  describe ".default_exam_date" do
    it "is the next 28 September with at least three weeks to prepare" do
      expect(described_class.default_exam_date(Date.new(2026, 3, 1))).to eq(Date.new(2026, 9, 28))
      expect(described_class.default_exam_date(Date.new(2026, 9, 23))).to eq(Date.new(2027, 9, 28))
    end
  end

  describe "validation" do
    it "wants an exam date between three weeks and two years away, each refusal a sentence" do
      start = Date.new(2026, 10, 5)

      expect(build(:study_plan, starts_on: start, exam_date: start + 21)).to be_valid
      expect(build(:study_plan, starts_on: start, exam_date: start + 730)).to be_valid
      expect(build(:study_plan, starts_on: start, exam_date: start + 20).tap(&:validate).errors.full_messages)
        .to eq([I18n.t("study_plans.errors.exam_date_too_close", minimum: 21)])
      expect(build(:study_plan, starts_on: start, exam_date: start + 731).tap(&:validate).errors.full_messages)
        .to eq([I18n.t("study_plans.errors.exam_date_too_far")])
    end

    it "needs a start and a known template" do
      expect(build(:study_plan, starts_on: nil, exam_date: Date.new(2027, 9, 28))).not_to be_valid
      expect(build(:study_plan, template: "weekends")).not_to be_valid
    end
  end

  it "rests on the template's weekdays" do
    plan = build(
      :study_plan, template: "five_days", starts_on: Date.new(2026, 10, 5),
      exam_date: Date.new(2026, 11, 30)
    )

    friday = Date.new(2026, 10, 9)
    dates = plan.study_dates(friday)

    expect(dates.first(3)).to eq([friday, friday + 3, friday + 4])
    expect(dates.last).to eq(Date.new(2026, 11, 27))
  end

  it "counts as missed only past days not done, and never a passed catch-up day" do
    plan = create(:study_plan)
    today = Date.new(2026, 10, 10)
    missed = create(:study_plan_day, study_plan: plan, date: today - 2)
    create(:study_plan_day, study_plan: plan, date: today - 3, completed_at: Time.current)
    create(:study_plan_day, study_plan: plan, date: today - 1, kind: "catch_up")
    create(:study_plan_day, study_plan: plan, date: today)

    expect(plan.missed_days(today)).to eq([missed])
  end

  it "goes with its student" do
    plan = create(:study_plan)
    create(:study_plan_day, study_plan: plan, exam: create(:exam, user: plan.user))

    expect { plan.user.destroy }.to change(StudyPlanDay, :count).to(0)
  end
end

require "rails_helper"

RSpec.describe StudyPlansHelper, type: :helper do
  let(:plan) { create(:study_plan) }
  let(:today) { Date.new(2026, 10, 7) }

  def day(kind = "topics", on: today + 1, **attributes)
    create(:study_plan_day, study_plan: plan, kind: kind, date: on, **attributes)
  end

  it "names a week within one month by its days, and one across two by both dates" do
    expect(helper.plan_week_range(Date.new(2026, 10, 5)..Date.new(2026, 10, 11))).to eq("5 – 11 de octubre")
    expect(helper.plan_week_range(Date.new(2026, 9, 28)..Date.new(2026, 10, 4)))
      .to eq("28 de septiembre – 4 de octubre")
  end

  it "says where a day stands" do
    unfinished = day(on: today - 1, exam: create(:exam, user: plan.user))

    expect(helper.plan_day_status(day(on: today - 2, completed_at: Time.current), today)).to eq(:done)
    expect(helper.plan_day_status(unfinished, today)).to eq(:in_progress)
    expect(helper.plan_day_status(day(on: today - 3), today)).to eq(:missed)
    expect(helper.plan_day_status(day, today)).to be_nil
  end

  it "does not count a catch-up day that went by as missed" do
    expect(helper.plan_day_status(day("catch_up", on: today - 1), today)).to be_nil
  end

  it "says whether a day brings a quiz, is for reading, or neither" do
    expect(helper.plan_day_workload(day("review"))).to eq("20 preguntas")
    expect(
      helper.plan_day_workload(
        day(
          on: today + 2,
          specialty: create(:specialty)
        )
      )
    ).to eq(I18n.t("study_plans.show.reading"))
    expect(helper.plan_day_workload(day("catch_up", on: today + 3))).to be_nil
  end

  describe "the way back to the calendar" do
    let(:date) { Date.new(2026, 10, 8) }

    it "opens the week unless the month was chosen last" do
      expect(helper.study_calendar_path(date)).to eq("/study_plan?week=2026-10-05")
    end

    it "opens the month when it was" do
      helper.request.cookies[:calendar_view] = "month"

      expect(helper.study_calendar_path(date)).to eq("/study_plan?month=2026-10")
    end

    it "ignores a remembered view it does not know" do
      helper.request.cookies[:calendar_view] = "fortnight"

      expect(helper.remembered_calendar_view).to eq("week")
    end
  end
end

require "rails_helper"

RSpec.describe "Study plans", type: :request do
  let(:student) { create(:user) }
  let(:today) { Date.new(2026, 10, 5) }
  let!(:syllabus) { create_syllabus }

  # Noon in Mexico City, well clear of the midnight day boundary.
  around { |example| travel_to(Time.find_zone("America/Mexico_City").local(2026, 10, 5, 12)) { example.run } }

  before { post session_path, params: { email: student.email, password: "contrasena-segura" } }

  def create_plan(days: 60, template: "every_day")
    StudyPlans::Builder.call(user: student, exam_date: (today + days).iso8601, template: template, today: today)
                       .payload[:plan]
  end

  def current_view
    Nokogiri::HTML(response.body).at_css("[aria-current='page']").text
  end

  it "turns away anyone not signed in" do
    delete session_path

    get study_plan_path

    expect(response).to redirect_to(new_session_path)
  end

  it "sends a student without a plan to make one" do
    %i[get_show get_edit patch_update post_catch_up delete_destroy].each do |action|
      verb, name = action.to_s.split("_", 2)
      path = name == "edit" ? edit_study_plan_path : (name == "catch_up" ? catch_up_study_plan_path : study_plan_path)
      public_send(verb, path)

      expect(response).to redirect_to(new_study_plan_path)
    end
  end

  describe "making one" do
    it "suggests the next exam and a six-day week" do
      get new_study_plan_path

      expect(response.body).to include(
        I18n.t("study_plans.new.title"), 'value="2027-09-28"',
        I18n.t("study_plans.templates.six_days")
      )
      expect(response.body).to match(/checked="checked"[^>]*value="six_days"|value="six_days"[^>]*checked="checked"/)
    end

    it "builds it from today and opens the calendar" do
      post study_plan_path, params: { study_plan: { exam_date: "2027-09-28", template: "five_days" } }

      expect(response).to redirect_to(study_plan_path)
      expect(student.reload.study_plan).to have_attributes(starts_on: today, template: "five_days")
      follow_redirect!
      expect(response.body).to include(I18n.t("study_plans.create.done"), "Cirugía General A 1")
    end

    it "says what is wrong with the date and keeps the form" do
      post study_plan_path, params: { study_plan: { exam_date: (today + 3).iso8601, template: "six_days" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("study_plans.errors.exam_date_too_close", minimum: 21))
      expect(StudyPlan.count).to eq(0)
    end

    it "is not offered twice" do
      create_plan

      get new_study_plan_path
      expect(response).to redirect_to(study_plan_path)
      post study_plan_path, params: { study_plan: { exam_date: "2027-09-28", template: "six_days" } }
      expect(response).to redirect_to(study_plan_path)
    end
  end

  describe "the calendar's month" do
    it "names each day's topics for the month, today first" do
      create_plan

      get study_plan_path(month: "2026-10")

      expect(response.body).to include(
        "Cirugía General A 1 · Cirugía General A 2", "octubre 2026",
        I18n.t("study_plans.kinds.case_workshop_of", specialty: "Cirugía General"), "specialty-amber", "ring-accent"
      )
      expect(response.body).to include(%(href="#{study_plan_path(month: "2026-11")}"))
      expect(response.body).not_to include(
        %(href="#{study_plan_path(month: "2026-09")}"),
        I18n.t("study_plans.show.behind", count: 1)
      )
    end

    it "moves between the months of the plan and no further" do
      create_plan

      get study_plan_path(month: "2026-12")

      expect(response.body).to include("diciembre 2026", %(href="#{study_plan_path(month: "2026-11")}"))
      expect(response.body).not_to include(%(href="#{study_plan_path(month: "2027-01")}"))
    end

    it "says a month outside the plan is empty, and ignores a month it cannot read" do
      create_plan

      get study_plan_path(month: "2027-01")
      expect(response.body).to include(I18n.t("study_plans.show.empty_month"))

      get study_plan_path(month: "never")
      expect(response.body).to include("octubre 2026")
    end

    it "marks done days, and names days missed with a way to catch up" do
      plan = create_plan
      plan.days.first.update!(completed_at: Time.current)
      travel 2.days

      get study_plan_path(month: "2026-10")

      expect(response.body).to include(
        I18n.t("study_plans.show.behind", count: 1), I18n.t("study_plans.show.catch_up"),
        I18n.t("study_plans.done"), I18n.t("study_plans.status.missed")
      )
    end
  end

  describe "the calendar's week" do
    def week_rows
      Nokogiri::HTML(response.body).css("[data-testid='week'] > li").map { |row| row.text.squish }
    end

    it "opens on this week, Monday to Sunday, each day with its topics and its quiz or reading" do
      create(
        :published_case, topic: syllabus["cirugia-general"].first,
        specialty: syllabus["cirugia-general"].first.specialty
      )
      create_plan

      get study_plan_path

      expect(response.body).to include("5 – 11 de octubre")
      expect(current_view).to eq(I18n.t("study_plans.show.view.week"))
      expect(week_rows.size).to eq(7)
      expect(week_rows.first).to start_with("lun 5 Cirugía General A 1 · Cirugía General A 2")
      expect(week_rows.first).to include(I18n.t("study_plans.show.quiz", count: 10))
      expect(week_rows.second).to include(I18n.t("study_plans.show.reading"))
      expect(week_rows.last).to start_with("dom 11")
      expect(response.body).to include(
        %(href="#{study_plan_path(week: "2026-10-12")}"), %(href="#{study_plan_path(month: "2026-10")}"),
        I18n.t("study_plans.show.week_done", done: 0, total: 7)
      )
      expect(response.body).not_to include(%(href="#{study_plan_path(week: "2026-09-28")}"))
    end

    it "shows the week of any date it is given, across two months when it falls that way" do
      create_plan

      get study_plan_path(week: "2026-10-29")

      expect(response.body).to include(
        "26 de octubre – 1 de noviembre", %(href="#{study_plan_path(week: "2026-10-19")}"),
        %(href="#{study_plan_path(month: "2026-10")}")
      )
    end

    it "names rest days, and ends on the exam with nothing after it" do
      create_plan(template: "six_days")

      get study_plan_path(week: "2026-11-30")

      expect(week_rows[3]).to include(
        I18n.t("study_plans.kinds.assessment"),
        I18n.t("study_plans.show.questions", count: 280)
      )
      expect(week_rows[4]).to include(I18n.t("study_plans.show.exam_day"))
      expect(week_rows[5..]).to all(include(I18n.t("study_plans.show.outside_plan")))
      expect(response.body).not_to include(%(href="#{study_plan_path(week: "2026-12-07")}"))

      get study_plan_path(week: "2026-10-05")
      expect(week_rows.last).to include(I18n.t("study_plans.day.rest"))
    end

    it "says a week outside the plan is empty, and ignores a week it cannot read" do
      create_plan

      get study_plan_path(week: "2027-01-04")
      expect(response.body).to include(I18n.t("study_plans.show.empty_week"))

      get study_plan_path(week: "someday")
      expect(response.body).to include("5 – 11 de octubre")
    end

    it "says which days are done, under way, or missed" do
      create(
        :published_case, topic: syllabus["cirugia-general"][2],
        specialty: syllabus["cirugia-general"].first.specialty
      )
      plan = create_plan
      plan.days.first.update!(completed_at: Time.current)
      travel 2.days
      post quiz_study_plan_day_path(today + 2)

      get study_plan_path

      %i[done missed in_progress].each_with_index do |status, index|
        expect(week_rows[index]).to end_with(I18n.t("study_plans.status.#{status}"))
      end
      expect(response.body).to include(I18n.t("study_plans.show.week_done", done: 1, total: 7))
    end
  end

  describe "remembering the view" do
    it "opens in whichever view was chosen last, and the day leads back to it" do
      plan = create_plan

      get study_plan_path(month: "2026-10")
      get study_plan_path
      expect(current_view).to eq(I18n.t("study_plans.show.view.month"))
      get study_plan_day_path(plan.days.first.date)
      expect(response.body).to include(%(href="#{study_plan_path(month: "2026-10")}"))

      get study_plan_path(week: "2026-10-12")
      get study_plan_path
      expect(response.body).to include("5 – 11 de octubre")
      get study_plan_day_path(plan.days.first.date)
      expect(response.body).to include(%(href="#{study_plan_path(week: "2026-10-05")}"))
    end

    it "opens the week when what it remembers is not a view" do
      create_plan
      cookies[:calendar_view] = "fortnight"

      get study_plan_path

      expect(response.body).to include("5 – 11 de octubre")
    end
  end

  describe "moving it" do
    it "moves what is left to the new date and week" do
      plan = create_plan
      plan.days.first.update!(completed_at: Time.current)

      get edit_study_plan_path
      expect(response.body).to include(I18n.t("study_plans.edit.title"), 'value="2026-12-04"')

      patch study_plan_path, params: { study_plan: { exam_date: "2027-01-15", template: "six_days" } }

      expect(response).to redirect_to(study_plan_path)
      expect(plan.reload).to have_attributes(exam_date: Date.new(2027, 1, 15), template: "six_days", starts_on: today)
    end

    it "keeps the form when the new date will not do" do
      create_plan

      patch study_plan_path, params: { study_plan: { exam_date: "2026-10-10", template: "six_days" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("study_plans.errors.exam_date_too_close", minimum: 21))
    end

    it "catches up from today" do
      plan = create_plan
      plan.days.first.update!(completed_at: Time.current)
      travel 2.days

      post catch_up_study_plan_path

      expect(response).to redirect_to(study_plan_path)
      expect(plan.reload.missed_days(today + 2)).to be_empty
    end

    it "says when there is nothing left to catch up onto" do
      plan = create_plan(days: 21)
      plan.days.first.update!(completed_at: Time.current)
      travel 30.days

      post catch_up_study_plan_path

      expect(response).to redirect_to(study_plan_path)
      expect(flash[:alert]).to eq(I18n.t("study_plans.rescheduler.no_room"))
    end

    it "starts over" do
      create_plan

      delete study_plan_path

      expect(response).to redirect_to(new_study_plan_path)
      expect(StudyPlan.count).to eq(0)
    end
  end

  describe "on the home screen" do
    before do
      create(
        :published_case, topic: syllabus["cirugia-general"].first,
        specialty: syllabus["cirugia-general"].first.specialty
      )
    end

    it "offers to make a plan" do
      get root_path

      expect(response.body).to include(I18n.t("home.dashboard.today_plan.create"), new_study_plan_path)
    end

    it "shows today's topics and starts their quiz" do
      create_plan

      get root_path

      expect(response.body).to include(
        I18n.t("home.dashboard.today_plan.label"), "Cirugía General A 1 · Cirugía General A 2",
        quiz_study_plan_day_path(today), I18n.t("home.dashboard.today_plan.start")
      )
    end

    it "says when today is done" do
      create_plan.days.first.update!(completed_at: Time.current)

      get root_path

      expect(response.body).to include(I18n.t("study_plans.done"))
      expect(response.body).not_to include(quiz_study_plan_day_path(today))
    end

    it "opens a reading day rather than starting a quiz with nothing in it" do
      ClinicalCase.update_all(topic_id: syllabus["urgencias"].last.id)
      create_plan

      get root_path

      expect(response.body).to include(I18n.t("home.dashboard.today_plan.open"), study_plan_day_path(today))
    end

    it "rests on a rest day" do
      create_plan(template: "six_days")
      travel 6.days # Sunday

      get root_path

      expect(response.body).to include(I18n.t("home.dashboard.today_plan.rest"), "specialty-none")
    end
  end
end

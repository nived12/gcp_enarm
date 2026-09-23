require "rails_helper"

RSpec.describe "Study plan days", type: :request do
  let(:student) { create(:user) }
  let(:today) { Date.new(2026, 10, 5) }
  let!(:syllabus) { create_syllabus }
  let(:surgery) { syllabus["cirugia-general"] }
  let(:plan) do
    StudyPlans::Builder.call(user: student, exam_date: (today + 60).iso8601, template: "six_days", today: today)
                       .payload[:plan]
  end
  let(:first_day) { plan.days.first }

  around { |example| travel_to(Time.find_zone("America/Mexico_City").local(2026, 10, 5, 12)) { example.run } }

  before do
    post session_path, params: { email: student.email, password: "contrasena-segura" }
    create(:published_case, topic: surgery.first, specialty: surgery.first.specialty, questions_count: 2)
  end

  def day_of(kind)
    plan.days.find_by!(kind: kind)
  end

  it "sends a student without a plan to make one" do
    get study_plan_day_path(today)

    expect(response).to redirect_to(new_study_plan_path)
  end

  it "is a 404 for a date that is not one" do
    plan

    get study_plan_day_path("yesterday")

    expect(response).to have_http_status(:not_found)
  end

  describe "the day" do
    it "names its topics, which of them have cases, and the quiz on them" do
      get study_plan_day_path(first_day.date)

      expect(response.body).to include(
        "Cirugía General A 1", I18n.t("study_plans.day.cases", count: 1), I18n.t("study_plans.day.no_cases"),
        I18n.t("study_plans.day.pass", number: 1, total: 2), "Cirugía General", I18n.t("study_plans.day.start.topics")
      )
    end

    it "is a reading day when none of its topics has cases yet" do
      reading = plan.days.kind_topics.second

      get study_plan_day_path(reading.date)

      expect(response.body).to include(I18n.t("study_plans.day.reading"), I18n.t("study_plans.day.mark_done"))
      expect(response.body).not_to include(quiz_study_plan_day_path(reading.date))
    end

    it "says what a workshop, a review, a simulacro and a catch-up day are for" do
      %w[case_workshop review assessment catch_up].each do |kind|
        get study_plan_day_path(day_of(kind).date)

        expect(response.body).to include(CGI.escapeHTML(I18n.t("study_plans.day.about.#{kind}")))
      end
      expect(response.body).to include(I18n.t("study_plans.day.mark_done"))
      expect(response.body).not_to include(I18n.t("study_plans.day.reading"))
    end

    it "rests on a day the plan leaves free" do
      plan

      get study_plan_day_path(today + 6)

      expect(response.body).to include(I18n.t("study_plans.day.rest"))
    end

    it "shows a done day, with its results when it had a quiz" do
      exam = create(:exam, user: student, status: "completed")
      first_day.update!(exam: exam)
      plan.days.second.update!(completed_at: Time.current)

      get study_plan_day_path(first_day.date)
      expect(response.body).to include(I18n.t("study_plans.day.done"), exam_path(exam))

      get study_plan_day_path(plan.days.second.date)
      expect(response.body).to include(I18n.t("study_plans.day.done"))
      expect(response.body).not_to include(I18n.t("study_plans.day.see_results"))
    end
  end

  describe "its quiz" do
    it "draws the day's topics and keeps the exam with the day" do
      post quiz_study_plan_day_path(first_day.date)

      exam = Exam.last
      expect(response).to redirect_to(exam_question_path(exam, 1))
      expect(exam.filters).to include("topic_ids" => [surgery.first.id], "question_count" => 10)
      expect(first_day.reload.exam).to eq(exam)
    end

    it "sends a free student past today's allowance to the plans" do
      student.update_column(:trial_ends_at, 1.day.ago)
      allow(SubscriptionAccess).to receive(:free_daily_questions).and_return(0)

      post quiz_study_plan_day_path(first_day.date)

      expect(response).to redirect_to(pricing_path)
      expect(first_day.reload.exam).to be_nil
    end

    it "picks up a quiz already started rather than drawing another" do
      post quiz_study_plan_day_path(first_day.date)
      exam = Exam.last

      get study_plan_day_path(first_day.date)
      expect(response.body).to include(I18n.t("study_plans.day.continue"))

      post quiz_study_plan_day_path(first_day.date)
      expect(response).to redirect_to(exam_path(exam))
      expect(Exam.count).to eq(1)
    end

    it "counts the day done once the quiz is finished" do
      post quiz_study_plan_day_path(first_day.date)
      patch complete_exam_path(Exam.last)

      expect(first_day.reload).to be_done
    end

    it "opens a simulacro on its answer sheet" do
      assessment = day_of("assessment")

      post quiz_study_plan_day_path(assessment.date)

      expect(Exam.last).to have_attributes(mode: "full_exam", feedback_timing: "at_end")
      expect(response).to redirect_to(exam_path(Exam.last))
    end

    it "says so when the bank has nothing for the day" do
      workshop = plan.days.kind_case_workshop.second

      post quiz_study_plan_day_path(workshop.date)

      expect(response).to redirect_to(study_plan_day_path(workshop.date))
      expect(flash[:alert]).to eq(I18n.t("exams.builder.nothing_matches"))
    end
  end

  it "marks a day without a quiz as done" do
    reading = plan.days.kind_topics.second

    patch complete_study_plan_day_path(reading.date)

    expect(response).to redirect_to(study_plan_day_path(reading.date))
    expect(reading.reload).to be_done
  end
end

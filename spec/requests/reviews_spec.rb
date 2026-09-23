require "rails_helper"

RSpec.describe "Reviews", type: :request do
  let(:student) { create(:user) }

  before { post session_path, params: { email: student.email, password: "contrasena-segura" } }

  def miss(kase = create(:published_case), days_ago: 1)
    travel_to(days_ago.days.ago) { sit(student, kase, %i[wrong right]) }
    kase
  end

  it "turns away anyone not signed in" do
    delete session_path

    get reviews_path

    expect(response).to redirect_to(new_session_path)
  end

  it "says honestly when nothing is due, and still offers pearls" do
    get reviews_path

    expect(response.body).to include(I18n.t("reviews.index.cases_none"), I18n.t("reviews.index.pearls_start"))
    expect(response.body).not_to include(I18n.t("reviews.index.start"))
  end

  it "counts what is due today and this week, and starts the session" do
    miss
    miss(days_ago: 0)
    create(:review_card, :pearl, user: student, due_on: student.study_date)

    get reviews_path

    expect(response.body).to include(
      I18n.t("reviews.index.cases_due", count: 1), I18n.t("reviews.index.cases_week", count: 1),
      I18n.t("reviews.index.pearls_due", count: 1)
    )

    post exams_path, params: { mode: "review" }

    exam = Exam.last
    expect(exam).to have_attributes(mode: "review", question_count: 2)
    expect(response).to redirect_to(exam_question_path(exam, 1))
  end

  it "sends the student back with a reason when the session has nothing to draw" do
    post exams_path, params: { mode: "review" }

    expect(response).to redirect_to(new_exam_path)
    expect(flash[:alert]).to eq(I18n.t("reviews.nothing_due"))
  end

  it "puts one line on the home screen, and the deck on the stats page" do
    create(:published_case)
    get root_path
    expect(response.body).to include(I18n.t("home.dashboard.due_none"), I18n.t("home.dashboard.due_pearls"))

    miss
    get root_path
    expect(response.body).to include(I18n.t("home.dashboard.due", count: 1), I18n.t("home.dashboard.due_link"))

    get stats_path
    expect(response.body).to include(I18n.t("reviews.summary.due", cases: 1, pearls: 0))
  end

  it "says nothing is due on the stats page when nothing is" do
    get stats_path

    expect(response.body).to include(I18n.t("reviews.summary.none"))
  end
end

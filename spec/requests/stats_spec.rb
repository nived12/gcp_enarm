require "rails_helper"

RSpec.describe "Stats", type: :request do
  let(:student) { create(:user) }
  let(:today) { student.study_date }

  before { post session_path, params: { email: student.email, password: "contrasena-segura" } }

  def studied(*days_ago, questions: 10)
    days_ago.each { |ago| student.study_days.create!(date: today - ago, questions_answered: questions) }
  end

  def answer(kase, correct:, status: "completed")
    exam = create(:exam, user: student, status: status, question_count: 1)
    exam_question = exam.exam_questions.create!(question: kase.questions.first, clinical_case: kase, position: 1)
    exam_question.create_answer!(correct: correct, answered_at: Time.current)
    exam.update!(score: correct ? 100 : 0) if status == "completed"
  end

  it "turns away anyone not signed in" do
    delete session_path

    get stats_path

    expect(response).to redirect_to(new_session_path)
  end

  it "gives a new student an empty page that says how to fill it" do
    get stats_path

    expect(response.body).to include(
      I18n.t("stats.show.empty.title"), I18n.t("stats.show.empty.start"),
      I18n.t("stats.streak.start", minimum: 10), I18n.t("stats.coverage.empty")
    )
    expect(response.body).not_to include(I18n.t("stats.show.by_difficulty"), I18n.t("stats.streak.freezes", count: 0))
  end

  it "shows the average, accuracy by difficulty and specialty, and the bank seen" do
    internal = create(:specialty, name: "Medicina Interna", position: 1)
    create(:specialty, name: "Urgencias", kind: "cross_cutting", position: 2)
    kase = create(:published_case, specialty: internal, difficulty: "high", questions_count: 1)
    answer(kase, correct: true)

    get stats_path

    expect(response.body).to include(
      "100%", I18n.t("stats.show.completed", count: 1), I18n.t("stats.show.tally", count: 1, total: 1),
      I18n.t("difficulties.high"), I18n.t("stats.show.no_questions"), "Medicina Interna",
      I18n.t("stats.coverage.area", seen: 1, published: 1), I18n.t("stats.coverage.none_published")
    )
    expect(response.body).not_to include(I18n.t("stats.coverage.neglected_title"))
  end

  it "has accuracy before it has an average, while the first exam is unfinished" do
    answer(create(:published_case, questions_count: 1), correct: false, status: "in_progress")

    get stats_path

    expect(response.body).to include(I18n.t("stats.show.no_average"), I18n.t("stats.show.tally", count: 0, total: 1))
  end

  it "names an area being left behind and offers to practise it" do
    internal = create(:specialty, name: "Medicina Interna", position: 1)
    family = create(:specialty, name: "Medicina Familiar", kind: "cross_cutting", position: 2)
    create_list(:published_case, 10, specialty: internal, questions_count: 1).each do |kase|
      answer(kase, correct: true)
    end
    create(:published_case, specialty: family, questions_count: 1)

    get stats_path
    expect(response.body).to include(
      I18n.t("stats.coverage.neglected_title"),
      I18n.t("stats.coverage.practice", name: "Medicina Familiar")
    )

    form = Nokogiri::HTML(response.body).at_css("[data-testid=neglected] form")
    post form["action"], params: form.css("input[type=hidden]").to_h { |input| [input["name"], input["value"]] }
    expect(Exam.last.exam_questions.map { |exam_question| exam_question.clinical_case.specialty }).to eq([family])
  end

  describe "the streak" do
    it "shows the freeze that covered a missed day, and what today still needs" do
      studied(*(2..8).to_a)
      studied(0, questions: 3)

      get stats_path

      expect(response.body).to include(
        I18n.t("stats.streak.today", answered: 3, minimum: 10), I18n.t("stats.streak.keep", remaining: 7),
        I18n.t("stats.streak.frozen", count: 1, dates: I18n.l(today - 1, format: :short))
      )
      expect(response.body).not_to include(I18n.t("stats.streak.best", count: 7))
    end

    it "keeps the best streak after one ends, and shows a freeze in the bank" do
      studied(*(19..30).to_a)
      studied(*(0..6).to_a)

      get stats_path

      expect(response.body).to include(I18n.t("stats.streak.best", count: 12), I18n.t("stats.streak.freezes", count: 1))
    end

    it "says when today already counts" do
      studied(0, questions: 12)

      get stats_path

      expect(response.body).to include(I18n.t("stats.streak.today_done", answered: 12))
      expect(response.body).not_to include(I18n.t("stats.streak.best", count: 1))
    end

    it "says a pearls session made today count, without claiming questions" do
      student.study_days.create!(date: today, pearls_reviewed: StudyDay::PEARLS_PER_SESSION)

      get stats_path

      expect(response.body).to include(I18n.t("stats.streak.today_done_pearls"))
    end

    it "sits under the average on the home screen and leads to the stats" do
      create(:published_case)

      get root_path
      expect(response.body).to include(
        I18n.t("home.dashboard.streak_none"),
        I18n.t("home.dashboard.streak_today", answered: 0, minimum: 10), stats_path
      )

      studied(1)
      get root_path
      expect(response.body).to include(I18n.t("home.dashboard.streak", count: 1))

      studied(0)
      get root_path
      expect(response.body).to include(
        I18n.t("home.dashboard.streak", count: 2),
        I18n.t("home.dashboard.streak_today_done")
      )
    end
  end
end

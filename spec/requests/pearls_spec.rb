require "rails_helper"

RSpec.describe "Pearls", type: :request do
  let(:student) { create(:user) }
  let(:kase) { create(:published_case, questions_count: 1) }
  let(:statement) do
    create(
      :recommendation, guideline_section: kase.questions.first.recommendation.guideline_section,
      text: "Se recomienda iniciar amoxicilina durante 10 días en la otitis media aguda."
    )
  end

  before { post session_path, params: { email: student.email, password: "contrasena-segura" } }

  def grade(recommendation, grade: "good", step: 0)
    post review_pearls_path, params: { recommendation_id: recommendation.id, grade: grade, step: step }
  end

  it "has an honest empty state when no statement can be a pearl" do
    get pearls_path

    expect(response.body).to include(I18n.t("pearls.show.empty.title"))
  end

  it "shows the statement with a phrase hidden, then all of it, its grade and year, and no figure" do
    kase.questions.first.recommendation.update!(text: "La mayoría de los pacientes mejora sin tratamiento.")
    statement

    get pearls_path

    body = response.body
    expect(body).to include(I18n.t("pearls.show.progress", position: 1, total: 10), I18n.t("pearls.card.reveal"))
    prompt = body.index("Se recomienda iniciar amoxicilina durante ")
    expect(prompt).to be < body.index(I18n.t("pearls.card.blank_label"))
    expect(body).to include(">10 días</strong>", kase.guideline.catalog_key, "2022", ">A<")
    expect(body).not_to include("<mark>", "<figure")
  end

  it "says when the pearl's guideline is past its validity" do
    kase.questions.first.recommendation.update!(text: "La mayoría de los pacientes mejora sin tratamiento.")
    statement.guideline.update!(year: 2012)

    get pearls_path

    expect(response.body).to include(I18n.t("exams.feedback.expired"))
  end

  it "grades a card, counts it, and moves the session on" do
    grade(statement, step: 3)

    expect(response).to redirect_to(pearls_path(step: 4))
    expect(ReviewCard.sole).to have_attributes(recommendation: statement, due_on: student.study_date + 1)
    expect(student.study_days.sole.pearls_reviewed).to eq(1)
  end

  it "grades a card the student already holds even after it left the pool" do
    create(:review_card, user: student, recommendation: statement, due_on: student.study_date)
    kase.update!(status: "retired")

    grade(statement)

    expect(response).to have_http_status(:see_other)
  end

  it "refuses a statement that is not a pearl, and a grade the buttons never send" do
    grade(create(:recommendation))
    expect(response).to have_http_status(:not_found)

    grade(statement, grade: "perfect")
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "says when today's new pearls are spent, and keeps the session where it was" do
    stub_const("Pearl::NEW_PER_DAY", 1)
    kase.questions.first.recommendation.update!(text: "La mayoría de los pacientes mejora sin tratamiento.")
    other = create(
      :recommendation, guideline_section: statement.guideline_section,
      text: "Se recomienda vigilar la glucosa cada 4 horas en el posoperatorio."
    )
    grade(statement, step: 0)

    get pearls_path(step: 1)
    expect(response.body).to include(I18n.t("pearls.show.new_allowance_spent.title", limit: 1))

    grade(other, step: 1)
    expect(response).to redirect_to(pearls_path(step: 1))
    expect(ReviewCard.pluck(:recommendation_id)).to eq([statement.id])
  end

  it "ends the session after ten cards and says whether today now counts" do
    get pearls_path(step: 10)
    expect(response.body).to include(I18n.t("pearls.done.streak_pending"))

    student.study_days.create!(date: student.study_date, pearls_reviewed: 10)
    get pearls_path(step: 99)
    expect(response.body).to include(I18n.t("pearls.done.title"), I18n.t("pearls.done.streak_kept", count: 1))
  end
end

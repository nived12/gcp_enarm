require "rails_helper"

RSpec.describe "Remediation report", type: :request do
  let(:student) { create(:user) }
  let(:shaky) { create(:topic, name: "Otitis media") }
  let(:solid) { create(:topic, name: "Crisis hipertensiva") }

  before { post session_path, params: { email: student.email, password: "contrasena-segura" } }

  def finished_exam(reason: nil, source: "live_site")
    exam = create(:exam, user: student, mode: "full_exam", question_count: 1)
    kase = create(:published_case, topic: shaky, questions_count: 2)
    kase.guideline.update!(source: source, year: 2012)
    kase.questions.first.recommendation.guideline_section.update!(chapter: "TRATAMIENTO", question_label: "PREGUNTA 3")
    sit(student, kase, [[:wrong, reason], [:wrong, reason]], exam: exam)
    sit(student, create(:published_case, topic: solid, questions_count: 2), %i[right right], exam: exam, finish: true)
    exam
  end

  it "names what to read after the exam, by the guideline's own menu, with year and link" do
    exam = finished_exam

    get exam_path(exam)

    expect(response.body).to include(
      I18n.t("remediation.title"), "Otitis media", I18n.t("remediation.tally", correct: 0, total: 2),
      "TRATAMIENTO › PREGUNTA 3 › RECOMENDACIONES", "2012", I18n.t("exams.feedback.expired"),
      I18n.t("remediation.misses", count: 2), exam.exam_questions.first.clinical_case.guideline.source_url
    )
    expect(response.body).not_to include("Crisis hipertensiva</h3>")
  end

  it "reads an undated guideline without calling it expired, and links nowhere it has no address" do
    exam = finished_exam
    exam.exam_questions.first.clinical_case.guideline.update!(document_url: nil, year: nil)

    get exam_path(exam)

    expect(response.body).to include(I18n.t("exams.feedback.undated"))
    expect(response.body).not_to include(I18n.t("exams.feedback.expired"), I18n.t("exams.feedback.open_guideline"))
  end

  it "has no reading for misses that were misreadings" do
    exam = finished_exam(reason: "misread_case")

    get exam_path(exam)

    expect(response.body).to include(I18n.t("remediation.no_reading"))
  end

  it "stays out of the results of a short practice exam" do
    exam = create(:exam, user: student, question_count: 1)
    sit(student, create(:published_case, topic: shaky, questions_count: 2), %i[wrong wrong], exam: exam, finish: true)

    get exam_path(exam)

    expect(response.body).not_to include(I18n.t("remediation.title"))
  end
end

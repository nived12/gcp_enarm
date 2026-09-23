require "rails_helper"

# The practice loop, at phone width because that is where it is used: nothing that helps
# answer before the answer; after it, the explanation, the cited statement and its figure.
RSpec.describe "Quiz Express", type: :system, viewport: :phone do
  let(:student) { create(:user, name: "Ana") }
  let!(:figure_case) do
    create(:published_case, questions_count: 2, figure: true, stem: "Paciente de 58 años con dolor torácico.")
  end

  before { create(:published_case, questions_count: 1, stem: "Mujer de 40 años con palpitaciones.") }

  it "explains each answer only after it, asks why a miss was missed, and reviews it at the end" do
    sign_in_as(student)
    click_button I18n.t("home.dashboard.start_quiz")

    expect(page).to have_text(I18n.t("exams.bar.position", position: 1, total: 3))
    expect(page).to have_no_text(label("exams.feedback.source"))
    expect(page).to have_no_css("figure")
    expect_no_sideways_scroll

    # A question can be left for later and come back to.
    click_link I18n.t("exams.question.skip")
    expect(page).to have_text(I18n.t("exams.bar.position", position: 2, total: 3))
    click_link I18n.t("exams.question.previous")
    # Every question here offers the same options, so wait for the first one itself.
    expect(page).to have_no_link(I18n.t("exams.question.previous"))

    answer_with("Troponina I")
    expect(page).to have_text(I18n.t("exams.question.wrong"))
    expect(page).to have_text(label("exams.feedback.source"))
    expect(page).to have_css("mark", text: "electrocardiograma de 12 derivaciones")
    expect(page).to have_text("Troponina I no es el estudio inicial")
    expect_no_sideways_scroll

    click_button I18n.t("exams.triage.reasons.misread_case")
    expect(page).to have_css("button[aria-pressed='true']", text: I18n.t("exams.triage.reasons.misread_case"))

    2.times do
      click_link I18n.t("exams.question.next")
      expect(page).to have_no_css("figure")
      answer_with("Electrocardiograma de 12 derivaciones")
      expect(page).to have_text(I18n.t("exams.question.right"))
    end

    # Any question is one tap away, to reread a miss before finishing.
    find("summary", text: I18n.t("exams.question.map.title")).click
    find("details[open] a[href$='/questions/1']").click
    expect(page).to have_text(I18n.t("exams.bar.position", position: 1, total: 3))
    expect(page).to have_text(I18n.t("exams.question.wrong"))
    expect(page).to have_text("Troponina I no es el estudio inicial")
    expect_no_sideways_scroll
    click_button I18n.t("exams.question.see_results")

    expect(page).to have_text("66.7%")
    expect(page).to have_text(I18n.t("exams.results.tally", correct: 2, total: 3))
    expect_no_sideways_scroll

    # The figure the cited statement points at belongs to the explanation.
    click_link text: "Pregunta 1 del caso #{figure_case.id}"
    expect(page).to have_text(label("exams.feedback.explanation"))
    expect(page).to have_css("figure img")
    expect(page).to have_link(I18n.t("shared.figure.open"))
    expect(Answer.find_by!(correct: false)).to be_error_misread_case

    visit exams_path
    expect(page).to have_text(I18n.t("exams.modes.quick_quiz"))
    expect(page).to have_text("66.7%")
  end
end

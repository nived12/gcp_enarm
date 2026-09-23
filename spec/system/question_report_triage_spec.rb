require "rails_helper"

# "Sugerir cambios" end to end, at desktop width because triage happens at a desk: a
# student reports a question in place, and an admin finds it, reads the case on the
# review screen, withdraws it and closes the report with a note.
RSpec.describe "Suggesting a change and triaging it", type: :system do
  let(:student) { create(:user, name: "Ana") }
  let(:admin) { create(:user, :admin, name: "Gabriela") }
  let!(:kase) { create(:published_case, questions_count: 1, stem: "Paciente de 58 años con dolor torácico.") }

  it "files the report without leaving the question, and the admin resolves it" do
    sign_in_as(student)
    click_button I18n.t("home.dashboard.start_quiz")
    answer_with("Troponina I")
    expect(page).to have_text(I18n.t("exams.question.wrong"))
    question_url = page.current_url

    find("summary", text: I18n.t("question_reports.panel.summary")).click
    find("label", text: I18n.t("question_reports.reasons.incorrect_answer")).click
    fill_in I18n.t("question_reports.panel.comment"), with: "La guía pide troponina antes."
    click_button I18n.t("question_reports.panel.submit")

    expect(page).to have_text(I18n.t("question_reports.panel.thanks"))
    expect(page.current_url).to eq(question_url)
    expect(page).to have_text(label("exams.feedback.explanation"))

    click_button I18n.t("navigation.sign_out")
    sign_in_as(admin)
    visit admin_root_path
    click_link I18n.t("admin.nav.question_reports")

    expect(page).to have_text("La guía pide troponina antes.")
    expect(page).to have_text(student.email)
    click_link I18n.t("admin.question_reports.open_case", id: kase.id)

    expect(page).to have_text(I18n.t("admin.clinical_cases.open_reports", count: 1))
    click_button I18n.t("admin.clinical_cases.actions.flag")
    expect(page).to have_text(I18n.t("admin.clinical_cases.flagged_notice"))
    expect(kase.reload).to be_status_flagged

    click_link I18n.t("admin.clinical_cases.triage_reports")
    fill_in I18n.t("admin.question_reports.note"), with: "Caso señalado para corregir la opción."
    click_button I18n.t("admin.question_reports.resolve")

    expect(page).to have_text(I18n.t("admin.question_reports.done.resolved"))
    expect(page).to have_text(I18n.t("admin.question_reports.empty.title"))
    expect(QuestionReport.last).to have_attributes(status: "resolved", resolved_by: admin)
  end
end

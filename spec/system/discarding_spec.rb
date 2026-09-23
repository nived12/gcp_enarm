require "rails_helper"

# An exam started by mistake, or finished and not wanted, can be taken out of the
# student's history and average — after they confirm it.
RSpec.describe "Discarding an exam", type: :system, viewport: :phone do
  let(:student) { create(:user, name: "Ana") }

  before { create(:published_case, questions_count: 1) }

  it "discards a quiz started by mistake from the home screen, only once confirmed" do
    sign_in_as(student)
    click_button I18n.t("home.dashboard.start_quiz")
    expect(page).to have_button(I18n.t("exams.question.submit"))
    visit root_path
    expect(page).to have_text(I18n.t("home.dashboard.unfinished", mode: I18n.t("exams.modes.quick_quiz")))

    dismiss_confirm { click_button I18n.t("exams.discard.button") }
    expect(page).to have_text(I18n.t("home.dashboard.unfinished", mode: I18n.t("exams.modes.quick_quiz")))

    accept_confirm { click_button I18n.t("exams.discard.button") }
    expect(page).to have_text(I18n.t("exams.discard.done"))
    expect(page).to have_no_text(I18n.t("home.dashboard.unfinished", mode: I18n.t("exams.modes.quick_quiz")))
  end

  it "discards a finished exam from the history, and the average forgets it" do
    sign_in_as(student)
    click_button I18n.t("home.dashboard.start_quiz")
    answer_with("Troponina I")
    click_button I18n.t("exams.question.see_results")
    expect(page).to have_text("0%")

    visit root_path
    expect(page).to have_text(I18n.t("home.dashboard.completed", count: 1))

    visit exams_path
    accept_confirm { click_button I18n.t("exams.discard.button") }
    expect(page).to have_text(I18n.t("exams.discard.done"))
    expect(page).to have_text(I18n.t("exams.index.empty.title"))

    visit root_path
    expect(page).to have_text(I18n.t("home.dashboard.no_average"))
  end
end

require "rails_helper"

# The review loop, at phone width because it is what a student does between consults: a
# case missed today comes back tomorrow in Repaso, and a pearls session keeps the streak.
# SCREENSHOTS=1 saves each screen under tmp/screenshots.
RSpec.describe "Review loop", type: :system, viewport: :phone do
  let(:student) { create(:user, name: "Ana") }
  let!(:kase) { create(:published_case, questions_count: 2, stem: "Paciente de 58 años con dolor torácico.") }

  before do
    section = kase.questions.first.recommendation.guideline_section
    8.times do |index|
      create(
        :recommendation, guideline_section: section,
        text: "Se recomienda iniciar el tratamiento en las primeras #{index + 2} horas del ingreso en urgencias."
      )
    end
  end

  def shot(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/#{name}.png").to_s, full_page: true) if ENV["SCREENSHOTS"]
  end

  it "brings a missed case back the next day, and counts a pearls session as a day studied" do
    sign_in_as(student)
    click_button I18n.t("home.dashboard.start_quiz")
    answer_with("Troponina I")
    expect(page).to have_text(I18n.t("exams.question.wrong"))
    click_link I18n.t("exams.question.next")
    answer_with("Electrocardiograma de 12 derivaciones")
    expect(page).to have_text(I18n.t("exams.question.right"))

    click_link I18n.t("app.name")
    expect(page).to have_text(I18n.t("home.dashboard.due_none"))

    travel 1.day do
      visit root_path
      expect(page).to have_text(I18n.t("home.dashboard.due", count: 1))
      expect_no_sideways_scroll
      shot("home_due")

      click_link I18n.t("home.dashboard.due", count: 1)
      expect(page).to have_text(I18n.t("reviews.index.cases_due", count: 1))
      shot("reviews_hub")
      click_button I18n.t("reviews.index.start")

      expect(page).to have_text(label("exams.modes.review"))
      expect(page).to have_text("Pregunta 1 del caso #{kase.id}")
      answer_with("Electrocardiograma de 12 derivaciones")
      expect(page).to have_text(I18n.t("exams.question.right"))

      visit reviews_path
      click_link I18n.t("reviews.index.pearls_start")
      StudyDay::PEARLS_PER_SESSION.times do |index|
        expect(page).to have_text(I18n.t("pearls.show.progress", position: index + 1, total: 10))
        expect(page).to have_no_css("mark")
        shot("pearl_prompt") if index.zero?
        find("summary", text: I18n.t("pearls.card.reveal")).click
        expect(page).to have_text(label("pearls.card.answer"))
        expect_no_sideways_scroll
        shot("pearl_revealed") if index.zero?
        click_button I18n.t("pearls.card.grades.good")
      end

      expect(page).to have_text(I18n.t("pearls.done.title"))
      expect(page).to have_text(I18n.t("pearls.done.streak_kept", count: 1))
      shot("pearls_done")
      click_link I18n.t("pearls.done.home")
      expect(page).to have_text(I18n.t("home.dashboard.streak", count: 1))
    end
  end

  it "names what to read after a long exam, and offers the weak spots as a quiz" do
    shaky = create(:topic, name: "Síndrome coronario agudo")
    solid = create(:topic, name: "Otitis media aguda")
    exam = create(:exam, user: student, mode: "full_exam", question_count: 1)
    kase.update!(topic: shaky)
    kase.questions.first.recommendation.guideline_section.update!(chapter: "DIAGNÓSTICO", question_label: "PREGUNTA 2")
    sit(student, kase, [[:wrong, "did_not_know"], :wrong], exam: exam)
    sit(student, create(:published_case, topic: shaky, questions_count: 2), %i[wrong right], exam: exam)
    4.times { sit(student, create(:published_case, topic: solid, questions_count: 2), %i[right right], exam: exam) }
    exam.complete!

    sign_in_as(student)
    visit exam_path(exam)
    expect(page).to have_text(label("remediation.title"))
    expect(page).to have_text("DIAGNÓSTICO › PREGUNTA 2 › RECOMENDACIONES")
    expect_no_sideways_scroll
    shot("remediation")

    visit new_exam_path(section: "custom")
    expect(page).to have_text(I18n.t("weak_spots.preset.title"))
    expect(page).to have_text("Síndrome coronario agudo")
    shot("weak_spots_preset")
    click_button I18n.t("weak_spots.preset.start", count: 20)
    expect(page).to have_text(label("exams.modes.weak_spots"))
  end
end

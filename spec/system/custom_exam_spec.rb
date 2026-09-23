require "rails_helper"

# The builder's own controls — pills and the topic search — and a sitting interrupted
# and taken up again.
RSpec.describe "Arma tu Examen", type: :system do
  let(:student) { create(:user, first_name: "Ana") }
  let!(:chosen) do
    create(
      :published_case, questions_count: 2, stem: "Paciente de 58 años con dolor torácico.",
      topic: create(:topic, name: "Síndrome coronario agudo")
    )
  end

  before do
    create(
      :published_case, questions_count: 1, stem: "Niño de 6 años con sibilancias.",
      topic: create(:topic, name: "Asma")
    )
  end

  it "builds an exam on a topic found by search, pauses it and picks up where it stopped" do
    sign_in_as(student)
    click_link I18n.t("home.dashboard.build_exam")
    expect(page).to have_no_text(I18n.t("exams.new.sections.mock.title"))
    find("label", exact_text: "10").click

    # Searching without accents finds the topic, and the closed picker names it.
    find("summary", text: I18n.t("exams.new.custom.all_topics")).click
    fill_in I18n.t("exams.new.custom.search_topic"), with: "sindrome"
    expect(page).to have_no_css("label", text: "Asma")
    find("label", text: "Síndrome coronario agudo").click
    click_button I18n.t("exams.new.custom.done_topics")
    expect(page).to have_css("summary", text: "Síndrome coronario agudo")

    click_button I18n.t("exams.new.custom.submit")
    expect(page).to have_text(chosen.stem)
    answer_with("Ecocardiograma")
    click_link I18n.t("exams.question.next")
    expect(page).to have_text(I18n.t("exams.bar.position", position: 2, total: 2))

    click_button I18n.t("exams.bar.pause")
    expect(page).to have_text(I18n.t("exams.paused.title"))
    expect(page).to have_text(I18n.t("exams.paused.progress", answered: 1, total: 2))

    visit root_path
    click_link href: %r{/exams/\d+\z}
    click_button I18n.t("exams.paused.resume")

    expect(page).to have_text(I18n.t("exams.bar.position", position: 2, total: 2))
    expect(page).to have_button(I18n.t("exams.question.submit"))
  end
end

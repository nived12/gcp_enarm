require "rails_helper"

# The loop the stats close, at phone width: a new student sees an honest empty page, one
# Quiz Express keeps today's streak, and the page then shows where they stand — including
# the part of the bank they have not touched.
RSpec.describe "Stats", type: :system, viewport: :phone do
  let(:student) { create(:user, first_name: "Ana") }
  let(:internal) { create(:specialty, name: "Medicina Interna", position: 1) }
  let(:family) { create(:specialty, name: "Medicina Familiar", kind: "cross_cutting", position: 2) }

  before { create_list(:published_case, 5, specialty: internal, difficulty: "high", questions_count: 2) }

  it "starts empty, counts today after ten answers, and shows accuracy and coverage" do
    sign_in_as(student)
    expect(page).to have_text(I18n.t("home.dashboard.streak_none"))
    click_link I18n.t("home.dashboard.streak_link")

    expect(page).to have_text(I18n.t("stats.show.empty.title"))
    expect(page).to have_text(I18n.t("stats.streak.start", minimum: 10))
    expect_no_sideways_scroll

    click_button I18n.t("stats.show.empty.start")
    10.times do |index|
      answer_with("Electrocardiograma de 12 derivaciones")
      index < 9 ? click_link(I18n.t("exams.question.next")) : click_button(I18n.t("exams.question.see_results"))
    end
    expect(page).to have_text("100%")
    # The bank grows while the student studies; what they have not met yet shows as unseen.
    create(:published_case, specialty: family, questions_count: 2)

    click_link I18n.t("app.name")
    expect(page).to have_text(I18n.t("home.dashboard.streak", count: 1))
    expect(page).to have_text(I18n.t("home.dashboard.streak_today_done"))
    click_link I18n.t("home.dashboard.streak_link")

    expect(page).to have_text(I18n.t("stats.streak.today_done", answered: 10))
    expect(page).to have_text(I18n.t("stats.show.tally", count: 10, total: 10))
    expect(page).to have_text(label("stats.show.by_difficulty"))
    expect(page).to have_text(I18n.t("stats.show.no_questions"))
    expect(page).to have_text(I18n.t("stats.coverage.area", seen: 5, published: 5))
    expect(page).to have_text(I18n.t("stats.coverage.area", seen: 0, published: 1))
    expect_no_sideways_scroll
  end

  describe "the heart's moments" do
    let(:heart) { "svg[data-controller=streak-heart]" }

    it "beats once when the day has counted, and flattens once when the streak is lost" do
      student.study_days.create!(date: student.study_date, questions_answered: 10)
      sign_in_as(student)
      # Home shows the heart first after signing in, so the beat plays there, once a day.
      expect(page).to have_css("#{heart}.streak-heart--beat")
      visit stats_path
      expect(page).to have_css("#{heart}[data-streak-state=active]")
      expect(page).to have_no_css("#{heart}.streak-heart--beat", wait: 0)

      student.study_days.update_all(date: student.study_date - 3)
      visit stats_path
      expect(page).to have_text(I18n.t("stats.streak.revive", minimum: 10))
      expect(page).to have_css("#{heart}.streak-heart--flatline")
      visit stats_path
      expect(page).to have_css("#{heart}[data-streak-state=lost]")
      expect(page).to have_no_css("#{heart}.streak-heart--flatline", wait: 0)
    end
  end
end

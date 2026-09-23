require "rails_helper"

# The calendar's promise, at phone width because that is where a student checks it: make a
# plan, see today's topics named on the home screen, and start the quiz on exactly those.
# SCREENSHOTS=1 keeps a picture of each screen under tmp/screenshots.
RSpec.describe "Study plan", type: :system, viewport: :phone do
  let(:student) { create(:user, first_name: "Ana") }
  let!(:syllabus) { create_syllabus }
  let(:first_topic) { syllabus["cirugia-general"].first }

  before do
    create_list(:published_case, 2, topic: first_topic, specialty: first_topic.specialty, questions_count: 1)
    create(
      :published_case, topic: syllabus["pediatria"].first, specialty: syllabus["pediatria"].first.specialty,
      stem: "Lactante de 6 meses con fiebre."
    )
  end

  def snap(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/study_plan_#{name}.png").to_s) if ENV["SCREENSHOTS"]
  end

  it "makes a plan, names today's topics at home, and quizzes exactly those" do
    sign_in_as(student)
    click_link I18n.t("home.dashboard.today_plan.create")

    expect(page).to have_text(I18n.t("study_plans.new.title"))
    expect_no_sideways_scroll
    snap("new")
    find("label", text: I18n.t("study_plans.templates.every_day")).click
    click_button I18n.t("study_plans.new.submit")

    expect(page).to have_text(I18n.t("study_plans.create.done"))
    expect(page).to have_link(href: study_plan_day_path(student.study_date), text: first_topic.name)
    expect_no_sideways_scroll
    snap("calendar")

    click_link I18n.t("app.name")
    within("[data-testid='today-plan']") do
      expect(page).to have_text(first_topic.name)
      snap("home")
      click_button I18n.t("home.dashboard.today_plan.start")
    end

    2.times do |index|
      expect(page).to have_text(I18n.t("exams.bar.position", position: index + 1, total: 2))
      answer_with("Electrocardiograma de 12 derivaciones")
      index.zero? ? click_link(I18n.t("exams.question.next")) : click_button(I18n.t("exams.question.see_results"))
    end
    expect(page).to have_text("100%")
    expect(page).to have_no_text("Lactante de 6 meses")

    click_link I18n.t("app.name")
    within("[data-testid='today-plan']") { expect(page).to have_text(I18n.t("study_plans.done")) }
    click_link first_topic.name

    expect(page).to have_text(I18n.t("study_plans.day.done"))
    expect_no_sideways_scroll
    snap("day")
  end
end

require "rails_helper"

# The calendar a student opens to know what the week asks of them: this week first, day by
# day, a step to the next, and the month when they want the longer view — which the
# calendar then keeps. SCREENSHOTS=1 keeps a picture of each screen under tmp/screenshots.
RSpec.describe "Study plan week", type: :system do
  let(:student) { create(:user, first_name: "Ana") }
  let!(:syllabus) { create_syllabus }
  let(:first_topic) { syllabus["cirugia-general"].first }
  let(:monday) { student.study_date.beginning_of_week(:monday) }

  # Started this Monday, so whatever day the suite runs on, the week holds the plan's
  # first day, done.
  before do
    create(:published_case, topic: first_topic, specialty: first_topic.specialty)
    StudyPlans::Builder.call(user: student, exam_date: (monday + 90).iso8601, template: "six_days", today: monday)
                       .payload[:plan].days.first.update!(completed_at: Time.current)
  end

  def snap(name)
    page.save_screenshot(Rails.root.join("tmp/screenshots/study_plan_week_#{name}.png").to_s) if ENV["SCREENSHOTS"]
  end

  def rows
    all("[data-testid='week'] > li")
  end

  it "walks the week on a phone, switches to the month, and comes back to it", viewport: :phone do
    sign_in_as(student)
    visit study_plan_path

    expect(rows.size).to eq(7)
    expect(page).to have_css("[aria-current='page']", text: I18n.t("study_plans.show.view.week"))
    expect_no_sideways_scroll
    snap("phone")

    find("a[aria-label='#{I18n.t("study_plans.show.next_week")}']").click
    expect(page).to have_current_path(study_plan_path(week: (monday + 7).iso8601))
    expect(rows.size).to eq(7)

    click_link I18n.t("study_plans.show.view.month")
    expect(page).to have_css("[aria-current='page']", text: I18n.t("study_plans.show.view.month"))
    expect_no_sideways_scroll
    first("[data-testid='plan-day']").click
    click_link I18n.t("study_plans.back_to_calendar")

    # Turbo first shows its cached copy of the calendar, then swaps in the fresh one; a
    # click on the cached copy's link lands on a node that is about to be detached.
    expect(page).to have_css("html:not([aria-busy]):not([data-turbo-preview])")
    expect(page).to have_css("[aria-current='page']", text: I18n.t("study_plans.show.view.month"))
    click_link I18n.t("study_plans.show.view.week")
    expect(page).to have_current_path(study_plan_path(week: monday.iso8601))
  end

  it "reads the same on a desktop in a dark theme", color_scheme: :dark do
    sign_in_as(student)
    visit study_plan_path

    expect(rows.size).to eq(7)
    expect(rows.first).to have_text(I18n.t("study_plans.status.done"))
    expect(body_background).to eq("rgb(14, 14, 24)")
    snap("desktop_dark")
  end
end

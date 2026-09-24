require "rails_helper"

# Reminders, from the invitation a new plan brings to the preferences that answer it, at
# phone width because a reminder is a phone's business.
RSpec.describe "Study reminders", type: :system, viewport: :phone do
  let(:student) { create(:user, first_name: "Ana") }

  before do
    create_syllabus
    sign_in_as(student)
    visit new_study_plan_path
    find("label", text: I18n.t("study_plans.templates.every_day")).click
    click_button I18n.t("study_plans.new.submit")
    expect(page).to have_text(I18n.t("study_plans.create.done"))
  end

  it "invites once after the plan is made, and can be put off" do
    within("[data-testid='reminder-invitation']") { click_button I18n.t("reminders.invitation.dismiss") }

    expect(page).to have_no_css("[data-testid='reminder-invitation']")
    expect_no_sideways_scroll
  end

  it "turns reminders on from the invitation", :web_push do
    click_link I18n.t("reminders.invitation.accept")

    within("#reminders") do
      # The browser was asked what it can do and one answer replaced the checking line.
      # Which one depends on the browser: headless Chromium reports notifications as
      # blocked, so subscribing itself is left to a real device.
      expect(page).to have_no_text(I18n.t("reminders.device.checking"))
      expect(page).to have_css("[data-push-subscription-target='state']:not([hidden])", count: 1)

      find("label", text: I18n.t("reminders.preferences.rules.study_days.label")).click
      find("label", text: I18n.t("reminders.preferences.email.label")).click
      find("label", text: "19:00").click
      click_button I18n.t("reminders.preferences.submit")
    end

    expect(page).to have_text(I18n.t("reminders.preferences.saved"))
    expect(student.reload.reminder_preference).to have_attributes(study_days: true, by_email: true, minute_of_day: 1140)
    expect_no_sideways_scroll
  end
end

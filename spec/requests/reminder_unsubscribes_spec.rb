require "rails_helper"

RSpec.describe "Reminder unsubscribe", type: :request do
  let(:student) { create(:user) }
  let!(:preference) { create(:reminder_preference, user: student, study_days: true, by_email: true) }
  let(:token) { student.generate_token_for(:reminder_unsubscribe) }

  it "asks before unsubscribing, so a mail scanner opening the link changes nothing" do
    get reminder_unsubscribe_path(token)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("reminders.unsubscribe.confirm"), student.email)
    expect(preference.reload.by_email).to be(true)
  end

  it "turns email reminders off signed out, keeping the reminders themselves" do
    post reminder_unsubscribe_path(token)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("reminders.unsubscribe.done.title"))
    expect(preference.reload).to have_attributes(by_email: false, study_days: true)
  end

  it "accepts a mail client's one-click POST, which carries no CSRF token" do
    ActionController::Base.allow_forgery_protection = true
    post reminder_unsubscribe_path(token), params: "List-Unsubscribe=One-Click",
      headers: { "Content-Type" => "application/x-www-form-urlencoded" }

    expect(response).to have_http_status(:ok)
    expect(preference.reload.by_email).to be(false)
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  it "works for an account that never saved preferences" do
    other = create(:user)

    post reminder_unsubscribe_path(other.generate_token_for(:reminder_unsubscribe))

    expect(other.reminder_preference.by_email).to be(false)
  end

  it "says plainly when the link is broken" do
    get reminder_unsubscribe_path("not-a-token")

    expect(response).to have_http_status(:not_found)
    expect(response.body).to include(I18n.t("reminders.unsubscribe.invalid.title"))

    post reminder_unsubscribe_path("not-a-token")
    expect(response).to have_http_status(:not_found)
  end
end

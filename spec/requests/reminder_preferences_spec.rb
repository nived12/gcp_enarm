require "rails_helper"

RSpec.describe "Reminder preferences", type: :request do
  let(:student) { create(:user, time_zone: "America/Cancun") }

  before { post session_path, params: { email: student.email, password: "contrasena-segura" } }

  def save(**attributes)
    patch account_reminders_path, params: { reminder_preference: attributes }
  end

  it "shows every reminder off at first, in the student's own zone" do
    get account_path

    expect(response.body).to include(I18n.t("reminders.preferences.promise"), "Cancún")
    %w[study_days streak_at_risk exam_countdown by_email].each do |field|
      expect(response.body).not_to match(/id="reminder_preference_#{field}"[^>]*checked/)
    end
  end

  it "points a student without a plan at making one" do
    get account_path

    expect(response.body).to include(I18n.t("reminders.preferences.no_plan"))

    create(:study_plan, user: student)
    get account_path
    expect(response.body).not_to include(I18n.t("reminders.preferences.no_plan"))
  end

  it "saves the reminders, the time and the email channel" do
    save(study_days: "1", exam_countdown: "1", by_email: "1", minute_of_day: "1170")

    expect(response).to redirect_to(account_path(anchor: "reminders"))
    expect(flash[:notice]).to eq(I18n.t("reminders.preferences.saved"))
    expect(student.reminder_preference).to have_attributes(
      study_days: true, streak_at_risk: false, exam_countdown: true, by_email: true, minute_of_day: 1170
    )
  end

  it "says so when the reminders have nowhere to go" do
    save(study_days: "1", by_email: "0")

    expect(flash[:notice]).to eq(I18n.t("reminders.preferences.saved_without_channel"))
  end

  it "counts a subscribed device as somewhere to go", :web_push do
    create(:push_subscription, user: student)

    save(study_days: "1", by_email: "0")

    expect(flash[:notice]).to eq(I18n.t("reminders.preferences.saved"))
  end

  it "refuses a time the form does not offer" do
    save(study_days: "1", minute_of_day: "7")

    expect(flash[:alert]).to eq(I18n.t("reminders.preferences.invalid"))
    expect(student.reload.reminder_preference).to be_nil
  end

  it "shows the device switch only once Web Push is configured" do
    get account_path
    expect(response.body).not_to include('data-controller="push-subscription"')

    WebPushHelpers.with_keys { get account_path }
    expect(response.body).to include('data-controller="push-subscription"', WebPushHelpers::VAPID.public_key)
    expect(response.body).to include(I18n.t("reminders.device.install.add"))
  end
end

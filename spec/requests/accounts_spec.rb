require "rails_helper"

RSpec.describe "Account", type: :request do
  let(:student) { create(:user, :trial_expired, name: "Dana") }

  before { post session_path, params: { email: student.email, password: "contrasena-segura" } }

  it "asks a visitor to sign in" do
    delete session_path

    get account_path

    expect(response).to redirect_to(new_session_path)
  end

  it "shows an empty purchase history and the way to the plans" do
    get account_path

    expect(response.body).to include("Dana", student.email, I18n.t("billing.account.history.empty.title"))
    expect(response.body).to include(I18n.t("billing.account.see_plans"))
  end

  it "lists every window bought, newest first, with what was paid" do
    freeze_time
    create(
      :entitlement, user: student, plan: "one_month", amount: 199, starts_at: 1.month.ago,
      expires_at: 1.day.from_now
    )
    create(
      :entitlement, user: student, plan: "twelve_months", amount: 1_099,
      starts_at: 1.day.from_now, expires_at: 1.day.from_now + 12.months
    )

    get account_path

    body = response.body
    newest, oldest = %w[twelve_months one_month].map { |code| body.index(I18n.t("billing.plans.#{code}.name")) }
    expect(newest).to be < oldest
    expect(body).to include("$1,099", "$199", I18n.t("billing.account.extend"))
    window = [1.day.from_now, 1.day.from_now + 12.months].map { |time| I18n.l(time.to_date, format: :long) }
    expect(body).to include(I18n.t("billing.account.history.window", from: window.first, to: window.last))
  end

  it "says a payment is being confirmed when the student returns from checkout" do
    get account_path(checkout: "success")

    expect(response.body).to include(I18n.t("billing.account.checkout_returned.title"))
  end

  describe "the time zone" do
    it "offers the Mexican zones as pills, with the student's own chosen" do
      travel_to(Time.utc(2026, 9, 23, 18, 5)) { get account_path }

      page = Nokogiri::HTML(response.body)
      expect(page.css("select")).to be_empty
      expect(page.css("input[name=time_zone]").map { |input| input["value"] }).to eq(User::TIME_ZONE_CHOICES.values)
      expect(page.at_css("input[name=time_zone][checked]")["value"]).to eq("America/Mexico_City")
      expect(response.body).to include(I18n.t("time_zones.option", name: "Cancún", time: "13:05"))
    end

    it "keeps a zone from sign-up that is not among the pills as one more" do
      student.update!(time_zone: "America/Bogota")

      get account_path

      checked = Nokogiri::HTML(response.body).at_css("input[name=time_zone][checked]")
      expect(checked["value"]).to eq("America/Bogota")
      expect(checked.parent.text).to include("Bogota")
    end

    it "changes the zone the study day ends in" do
      patch account_path, params: { time_zone: "America/Tijuana" }

      expect(response).to redirect_to(account_path)
      expect(flash[:notice]).to eq(I18n.t("time_zones.updated"))
      expect(student.reload.study_date(Time.utc(2026, 9, 23, 10, 30))).to eq(Date.new(2026, 9, 22))
    end

    it "refuses a zone that does not exist" do
      patch account_path, params: { time_zone: "Mars/Olympus_Mons" }

      expect(flash[:alert]).to eq(I18n.t("time_zones.invalid"))
      expect(student.reload.time_zone).to eq("America/Mexico_City")
    end
  end
end

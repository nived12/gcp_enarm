require "rails_helper"

RSpec.describe "Pricing", type: :request do
  def sign_in(user)
    post session_path, params: { email: user.email, password: "contrasena-segura" }
  end

  it "shows a visitor the four windows, and says payments are coming while none are configured" do
    get pricing_path

    expect(response).to have_http_status(:ok)
    Plan.all.each { |plan| expect(response.body).to include(I18n.t("billing.plans.#{plan.code}.name")) }
    expect(response.body).to include("$1,099", "≈ $92 al mes", I18n.t("pricing.unavailable"))
    expect(response.body).not_to include(checkouts_path)
  end

  describe "with payments configured", :stripe do
    it "offers a visitor sign-up rather than checkout" do
      get pricing_path

      expect(response.body).to include(I18n.t("pricing.sign_up_to_buy"))
      expect(response.body).not_to include(checkouts_path)
    end

    it "lets a signed-in student choose a window, outside Turbo" do
      sign_in(create(:user))

      get pricing_path

      expect(response.body).to include(checkouts_path(plan: "one_month"), 'data-turbo="false"')
      expect(response.body).to include(I18n.t("pricing.choose", plan: I18n.t("billing.plans.one_month.name")))
    end
  end

  describe "the student's current access" do
    let(:long_date) { ->(time) { I18n.l(time.to_date, format: :long) } }

    it "names a granted window first" do
      user = create(:user, :granted_premium)
      sign_in(user)

      get pricing_path

      expect(response.body).to include(I18n.t("billing.access.granted", date: long_date.(user.granted_premium_until)))
    end

    it "names the end of a paid window" do
      user = create(:user, :trial_expired)
      entitlement = create(:entitlement, user: user)
      sign_in(user)

      get pricing_path

      expect(response.body).to include(
        CGI.escapeHTML(
          I18n.t(
            "billing.access.paid",
            date: long_date.(entitlement.expires_at)
          )
        )
      )
    end

    it "names the end of the trial" do
      user = create(:user)
      sign_in(user)

      get pricing_path

      expect(response.body).to include(I18n.t("billing.access.trial", date: long_date.(user.reload.trial_ends_at)))
    end

    it "states the free allowance" do
      sign_in(create(:user, :trial_expired))

      get pricing_path

      expect(response.body).to include(I18n.t("billing.access.free", limit: 10))
    end
  end
end

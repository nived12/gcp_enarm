require "rails_helper"

# The purchase path at phone width: plans, the redirect to Stripe's hosted page, and back
# to an account that shows the new window. Stripe is never reached. The Checkout Session
# is created against a WebMock stub; the browser's POST to /checkouts is fetched by
# Playwright without following the redirect — a route handler never sees a redirect's
# target, so intercepting checkout.stripe.com itself would let the browser load it — and
# the webhook is delivered by hand, signed with the test secret.
RSpec.describe "Buying an access window", type: :system, viewport: :phone, stripe: true do
  let(:student) { create(:user, :trial_expired, first_name: "Ana") }
  let(:hosted_page) { "https://checkout.stripe.com/c/pay/cs_test_system" }
  let(:redirects) { Queue.new }

  # Lets the app answer the POST, records where it redirected, and shows a stand-in page.
  def hold_checkout_redirect(route, _request)
    response = route.fetch(maxRedirects: 0)
    redirects << [response.status, response.headers["location"]]
    route.fulfill(status: 200, contentType: "text/html", body: "<h1>Pago simulado</h1>")
  end

  before do
    stub_checkout_session(url: hosted_page, id: "cs_test_system")
    page.driver.with_playwright_page do |browser_page|
      browser_page.context.route("**/checkouts*", method(:hold_checkout_redirect))
    end
  end

  it "sends the chosen window to Stripe's hosted page, then shows it once the payment is confirmed" do
    sign_in_as(student)
    click_link I18n.t("pricing.nav")

    expect(page).to have_text(I18n.t("pricing.headline"))
    expect(page).to have_text(I18n.t("billing.access.free", limit: 20))
    expect_no_sideways_scroll

    within("[data-plan='three_months']") do
      click_button I18n.t("pricing.choose", plan: I18n.t("billing.plans.three_months.name"))
    end

    expect(page).to have_text("Pago simulado")
    expect(redirects.pop(timeout: 5)).to eq([303, hosted_page])
    expect(
      a_request(:post, BillingHelpers::CHECKOUT_SESSIONS_URL).with do |request|
        Rack::Utils.parse_nested_query(request.body)["metadata"] == { "user_id" => student.id.to_s, "plan_code" => "three_months" }
      end
    ).to have_been_made.once

    visit account_path(checkout: "success")
    expect(page).to have_text(I18n.t("billing.account.checkout_returned.title"))
    expect(page).to have_text(I18n.t("billing.account.history.empty.title"))

    payload = stripe_event_json(session: checkout_session_payload(user: student, id: "cs_test_system"))
    Billing::StripeWebhookHandler.call(payload: payload, signature: stripe_signature(payload))

    visit account_path
    expect(page).to have_text("$449")
    expect(page).to have_text(I18n.t("billing.access.paid", date: I18n.l(3.months.from_now.to_date, format: :long)))
    expect_no_sideways_scroll
  end
end

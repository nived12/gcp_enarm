require "rails_helper"

# "Continuar con Google" on a phone, with OmniAuth's test mode standing in for Google.
# The browser is told it is in Tijuana, so the zone that reaches the account can only
# have come from the hidden field posted with the button.
Capybara.register_driver(:playwright_phone_tijuana) do |app|
  Capybara::Playwright::Driver.new(
    app, browser_type: :chromium, headless: ENV["HEADED"].blank?, viewport: VIEWPORTS.fetch(:phone),
    locale: "es-MX", timezoneId: "America/Tijuana",
    playwright_cli_executable_path: Rails.root.join("node_modules/.bin/playwright").to_s
  )
end

RSpec.describe "Signing up with Google", :google, type: :system do
  before { driven_by :playwright_phone_tijuana }

  it "creates the account from the Google profile and shows it linked" do
    mock_google

    visit new_registration_path
    expect_no_sideways_scroll
    button = find("button", text: I18n.t("identities.google.continue"))
    expect(button.evaluate_script("this.getBoundingClientRect().height")).to be >= 44
    button.click

    expect(page).to have_text(I18n.t("identities.outcomes.created"))
    expect(page).to have_text(I18n.t("home.dashboard.greeting", name: "Dana"))
    user = User.find_by!(email: "dana.rios@gmail.com")
    expect([ user.full_name, user.time_zone ]).to eq([ "Dana Ríos Vega", "America/Tijuana" ])

    visit account_path
    expect(page).to have_text(I18n.t("identities.account.google_linked", email: "dana.rios@gmail.com"))
    expect(page).to have_link(I18n.t("identities.account.set_password"))
    expect_no_sideways_scroll
  end
end

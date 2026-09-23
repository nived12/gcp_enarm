require "rails_helper"

# The browser's own time zone reaches the account at sign-up, and the student can change
# it afterwards. The browser here is told it is in Cancún, which is not the default.
Capybara.register_driver(:playwright_cancun) do |app|
  Capybara::Playwright::Driver.new(
    app, browser_type: :chromium, headless: ENV["HEADED"].blank?, viewport: VIEWPORTS.fetch(:phone),
    locale: "es-MX", timezoneId: "America/Cancun",
    playwright_cli_executable_path: Rails.root.join("node_modules/.bin/playwright").to_s
  )
end

RSpec.describe "Signing up", type: :system do
  before { driven_by :playwright_cancun }

  it "takes the time zone from the browser, and lets the student change it" do
    visit new_registration_path
    fill_in I18n.t("attributes.name"), with: "Dana"
    fill_in I18n.t("attributes.email"), with: "dana@example.com"
    fill_in I18n.t("attributes.password"), with: "contrasena-segura"
    fill_in I18n.t("attributes.password_confirmation"), with: "contrasena-segura"
    click_button I18n.t("registrations.new.submit")

    expect(page).to have_text(I18n.t("registrations.create.welcome"))
    expect(User.find_by!(email: "dana@example.com").time_zone).to eq("America/Cancun")

    visit account_path
    expect(page).to have_checked_field("time_zone_America/Cancun", visible: :all)
    find("label", text: "Tijuana").click
    click_button I18n.t("time_zones.submit")

    expect(page).to have_text(I18n.t("time_zones.updated"))
    expect(User.find_by!(email: "dana@example.com").time_zone).to eq("America/Tijuana")
  end
end

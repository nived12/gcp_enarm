require "rails_helper"

# Light and dark are equals in the design, so dark gets walked like light: every screen
# a student sees, at phone width, painted from the dark tokens and nothing off-screen.
RSpec.describe "Dark mode", type: :system, viewport: :phone do
  let(:student) { create(:user, first_name: "Ana") }

  # --ground in application.tailwind.css, as the browser reports it.
  LIGHT_GROUND = "rgb(255, 252, 245)".freeze
  DARK_GROUND = "rgb(14, 14, 24)".freeze

  before { create(:published_case, questions_count: 2, figure: true) }

  context "when the system is dark", color_scheme: :dark do
    it "paints every screen of a sitting dark, without anything off-screen" do
      sign_in_as(student)
      expect(body_background).to eq(DARK_GROUND)

      screens = -> {
        expect(body_background).to eq(DARK_GROUND)
        expect_no_sideways_scroll
      }

      click_link I18n.t("home.dashboard.mock_exam")
      screens.call
      visit new_exam_path(section: "custom")
      screens.call

      visit root_path
      click_button I18n.t("home.dashboard.start_quiz")
      screens.call
      answer_with("Troponina I")
      expect(page).to have_text(label("exams.feedback.source"))
      screens.call

      click_button I18n.t("exams.bar.pause")
      expect(page).to have_text(I18n.t("exams.paused.title"))
      screens.call
    end

    it "switches to light on request and remembers it across pages and reloads" do
      sign_in_as(student)

      click_button I18n.t("shared.theme.toggle")
      expect(body_background).to eq(LIGHT_GROUND)

      visit exams_path
      expect(body_background).to eq(LIGHT_GROUND)
      refresh
      expect(body_background).to eq(LIGHT_GROUND)
    end
  end

  context "when the system is light" do
    it "starts light and switches to dark on request" do
      sign_in_as(student)
      expect(body_background).to eq(LIGHT_GROUND)

      click_button I18n.t("shared.theme.toggle")

      expect(body_background).to eq(DARK_GROUND)
    end
  end
end

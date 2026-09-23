# Shared steps for the end-to-end specs in spec/system.
module SystemHelpers
  def sign_in_as(user)
    visit new_session_path
    fill_in I18n.t("attributes.email"), with: user.email
    fill_in I18n.t("attributes.password"), with: "contrasena-segura"
    click_button I18n.t("sessions.new.submit")
    expect(page).to have_text(I18n.t("home.dashboard.greeting", name: user.first_name))
  end

  # Waits for the answer form first: after "Siguiente" the page still holding an
  # explanation has none, and its options can carry the same text as the next question's.
  def answer_with(text)
    expect(page).to have_button(I18n.t("exams.question.submit"))
    find("label", text: text).click
    click_button I18n.t("exams.question.submit")
  end

  # Eyebrows are uppercased by CSS, and Capybara reads the rendered text.
  def label(key, **options)
    /#{Regexp.escape(I18n.t(key, **options))}/i
  end

  # Nothing on a page may be wider than the phone it is on.
  def expect_no_sideways_scroll
    expect(page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")).to be(true)
  end

  # The colour the page is actually painted in, as the browser computed it.
  def body_background
    page.evaluate_script("getComputedStyle(document.body).backgroundColor")
  end
end

RSpec.configure { |config| config.include SystemHelpers, type: :system }

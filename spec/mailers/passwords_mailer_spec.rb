require "rails_helper"

RSpec.describe PasswordsMailer do
  include Rails.application.routes.url_helpers

  let(:user) { create(:user, email_address: "gabriela@example.com") }
  let(:mail) { described_class.reset(user) }

  it "addresses the user with a Spanish subject" do
    expect(mail.to).to eq(["gabriela@example.com"])
    expect(mail.subject).to eq(I18n.t("passwords_mailer.reset.subject"))
  end

  it "carries a working reset link in both parts" do
    token = user.password_reset_token
    allow(user).to receive(:password_reset_token).and_return(token)

    html, text = described_class.reset(user).body.parts.map { |part| part.body.to_s }

    expect(html).to include(edit_password_url(token, host: "example.com"))
    expect(text).to include(edit_password_url(token, host: "example.com"))
  end

  it "states when the link expires" do
    expect(mail.body.encoded).to include("15")
  end
end

require "rails_helper"

RSpec.describe EmailVerificationsMailer do
  include Rails.application.routes.url_helpers

  let(:user) { create(:user, :unverified, email: "gabriela@example.com") }
  let(:mail) { described_class.verify(user) }

  it "addresses the user by name with a Spanish subject" do
    expect(mail.to).to eq(["gabriela@example.com"])
    expect(mail[:to].display_names).to eq(["Gabriela Guadarrama López"])
    expect(mail.subject).to eq(I18n.t("email_verifications_mailer.verify.subject"))
    expect(mail.text_part.body.to_s).to include(I18n.t("email_verifications_mailer.verify.greeting", name: "Gabriela"))
  end

  it "sends from the no-reply address with no reply-to" do
    expect(mail.from).to eq(["no-responder@gpcenarm.com"])
    expect(mail.reply_to).to be_nil
  end

  it "carries a link that verifies this account in both parts" do
    text, html = mail.text_part.body.to_s, mail.html_part.body.to_s
    token = text[%r{/email_verification/(\S+)}, 1]

    expect(html).to include(%(href="#{verify_email_url(token, host: "example.com")}"))
    expect(User.find_by_token_for(:email_verification, token)).to eq(user)
  end
end

require "rails_helper"

RSpec.describe RemindersMailer do
  include Rails.application.routes.url_helpers

  let(:user) { create(:user, email: "gabriela@example.com") }
  let(:message) do
    { title: "Tu plan de hoy", lines: ["Hoy toca: Repaso mixto.", "Llevas 3 días de racha."],
   path: "/study_plan/days/2026-10-06" }
  end
  let(:mail) { described_class.reminder(user, message) }

  it "carries the reminder's own words, as the notification does" do
    expect(mail.to).to eq(["gabriela@example.com"])
    expect(mail.subject).to eq("Tu plan de hoy")
    mail.body.parts.each do |part|
      expect(part.body.to_s).to include("Hoy toca: Repaso mixto.", "Llevas 3 días de racha.")
      expect(part.body.to_s).to include("http://example.com/study_plan/days/2026-10-06")
    end
  end

  it "offers one-click unsubscribe to mail clients and a link that works signed out" do
    unsubscribe = mail["List-Unsubscribe"].value[/\A<(.+)>\z/, 1]
    token = unsubscribe[%r{/reminders/unsubscribe/(.+)\z}, 1]

    expect(mail["List-Unsubscribe-Post"].value).to eq("List-Unsubscribe=One-Click")
    expect(User.find_by_token_for(:reminder_unsubscribe, token)).to eq(user)
    mail.body.parts.each { |part| expect(part.body.to_s).to include(unsubscribe) }
  end
end

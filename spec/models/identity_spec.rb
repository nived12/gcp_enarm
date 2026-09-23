require "rails_helper"

RSpec.describe Identity do
  let(:user) { create(:user) }

  it "belongs to one account per provider, and one person per provider" do
    user.identities.create!(provider: "google_oauth2", uid: "1")

    expect(user.identities.build(provider: "google_oauth2", uid: "2")).not_to be_valid
    expect(create(:user).identities.build(provider: "google_oauth2", uid: "1")).not_to be_valid
    expect(create(:user).identities.build(provider: "google_oauth2", uid: "")).not_to be_valid
  end

  it "is available only with both Google credentials" do
    expect(described_class.google_available?).to be(false)

    ENV["GOOGLE_CLIENT_ID"] = "id"
    expect(described_class.google_available?).to be(false)

    ENV["GOOGLE_CLIENT_SECRET"] = "secret"
    expect(described_class.google_available?).to be(true)
  ensure
    ENV.delete("GOOGLE_CLIENT_ID")
    ENV.delete("GOOGLE_CLIENT_SECRET")
  end
end

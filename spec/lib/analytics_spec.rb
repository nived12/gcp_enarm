require "rails_helper"

RSpec.describe Analytics do
  let(:user) { build_stubbed(:user) }

  after do
    ENV.delete("POSTHOG_API_KEY")
    described_class.reset!
  end

  it "does nothing and builds no client without a key" do
    allow(PostHog::Client).to receive(:new)

    expect(described_class.capture(user, "checkout_started")).to be_nil
    expect(PostHog::Client).not_to have_received(:new)
  end

  it "sends the event under the user's id once a key is set, reusing one client" do
    ENV["POSTHOG_API_KEY"] = "phc_test"
    client = instance_double(PostHog::Client, capture: true)
    allow(PostHog::Client).to receive(:new).and_return(client)

    2.times { described_class.capture(user, "checkout_started", plan: "one_month") }

    expect(PostHog::Client).to have_received(:new).once
      .with(api_key: "phc_test", host: Analytics::DEFAULT_HOST)
    expect(client).to have_received(:capture).twice
      .with(distinct_id: user.id.to_s, event: "checkout_started", properties: { plan: "one_month" })
  end
end

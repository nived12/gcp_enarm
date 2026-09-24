require "rails_helper"

RSpec.describe PushNotificationJob, :web_push do
  let(:subscription) { create(:push_subscription) }

  it "sends through the sender" do
    stub = stub_request(:post, subscription.endpoint).to_return(status: 201)

    described_class.perform_now(subscription, "{}", 60)

    expect(stub).to have_been_requested
  end

  it "retries a push service that is down" do
    stub_request(:post, subscription.endpoint).to_return(status: 500)

    expect { described_class.perform_now(subscription, "{}", 60) }.to have_enqueued_job(described_class)
  end

  it "drops a job whose subscription was deleted before it ran" do
    described_class.perform_later(subscription, "{}", 60)
    subscription.destroy!

    expect { perform_enqueued_jobs }.not_to raise_error
  end
end

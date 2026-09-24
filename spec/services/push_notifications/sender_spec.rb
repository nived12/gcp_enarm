require "rails_helper"

RSpec.describe PushNotifications::Sender, :web_push do
  let(:subscription) { create(:push_subscription, endpoint: "https://fcm.googleapis.com/fcm/send/device") }
  let(:payload) { { title: "Tu plan de hoy", body: "Hoy toca: Repaso mixto.", path: "/" }.to_json }

  def send_push
    described_class.call(subscription: subscription, payload: payload, ttl: 3_600)
  end

  it "posts the encrypted payload, signed with the VAPID key, to the browser's push service" do
    stub = stub_request(:post, subscription.endpoint)
      .with(headers: { "Ttl" => "3600", "Content-Encoding" => "aes128gcm", "Authorization" => /\Avapid t=.+,k=.+\z/ })
      .to_return(status: 201)

    expect(send_push).to be_success
    expect(stub).to have_been_requested
  end

  [404, 410].each do |status|
    it "deletes a subscription the push service answers #{status} for" do
      stub_request(:post, subscription.endpoint).to_return(status: status)

      expect(send_push).to be_failure
      expect(PushSubscription.exists?(subscription.id)).to be(false)
    end
  end

  it "keeps the subscription when the push service refuses the signature" do
    stub_request(:post, subscription.endpoint).to_return(status: 403)

    expect(send_push).to be_failure
    expect(PushSubscription.exists?(subscription.id)).to be(true)
  end

  it "raises throttling and outages so the job can retry them" do
    stub_request(:post, subscription.endpoint).to_return({ status: 429 }, { status: 503 })

    expect { send_push }.to raise_error(WebPush::TooManyRequests)
    expect { send_push }.to raise_error(WebPush::PushServiceError)
  end
end

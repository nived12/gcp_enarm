require "rails_helper"

RSpec.describe PushSubscription do
  %w[
    https://fcm.googleapis.com/fcm/send/abc
    https://updates.push.services.mozilla.com/wpush/v2/abc
    https://web.push.apple.com/QGx1
    https://wns2-by3p.notify.windows.com/w/?token=abc
  ].each do |endpoint|
    it "accepts the push service at #{URI(endpoint).host}" do
      expect(build(:push_subscription, endpoint: endpoint)).to be_valid
    end
  end

  # The server POSTs to whatever is stored here, so anything else would let a forged
  # subscription aim the reminder job at an arbitrary address.
  [
    "http://fcm.googleapis.com/fcm/send/abc",
    "https://attacker.example/fcm.googleapis.com",
    "https://fcm.googleapis.com.attacker.example/send",
    "https://169.254.169.254/latest/meta-data",
    "not a url at all",
    "https://exa mple.com"
  ].each do |endpoint|
    it "refuses #{endpoint.inspect}" do
      expect(build(:push_subscription, endpoint: endpoint)).not_to be_valid
    end
  end

  it "needs both keys the browser gave" do
    expect(build(:push_subscription, p256dh_key: "")).not_to be_valid
    expect(build(:push_subscription, auth_key: nil)).not_to be_valid
  end

  it "is invisible without a VAPID pair" do
    expect(described_class.enabled?).to be(false)
  end

  it "signs with the configured pair and the support address", :web_push do
    expect(described_class.enabled?).to be(true)
    expect(described_class.public_key).to eq(WebPushHelpers::VAPID.public_key)
    expect(described_class.vapid).to include(
      subject: "mailto:soporte@gpcenarm.com", private_key: WebPushHelpers::VAPID.private_key
    )
  end
end

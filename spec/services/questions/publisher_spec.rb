require "rails_helper"

RSpec.describe Questions::Publisher do
  it "publishes the drafts a second opinion supported" do
    kase = create(:clinical_case, verification_verdict: "supported")

    expect(described_class.call.payload).to eq(published: 1, withdrawn: 0, live: 1)
    expect(kase.reload).to be_status_published
  end

  it "holds back every case the verifier did not support, or has not read" do
    cases = [nil, "ambiguous", "unsupported"].map { |verdict| create(:clinical_case, verification_verdict: verdict) }

    described_class.call

    expect(cases.map { |kase| kase.reload.status }).to all(eq("draft"))
  end

  # The pilot's four cases written around a guideline figure were supported and then
  # retired by hand. A person's decision outranks a model's agreement.
  it "never publishes a withdrawn case, whatever the verifier said" do
    retired = create(:clinical_case, verification_verdict: "supported", status: "retired")
    flagged = create(:clinical_case, verification_verdict: "supported", status: "flagged")

    described_class.call

    expect([retired.reload.status, flagged.reload.status]).to eq(%w[retired flagged])
  end

  it "pulls back a published case that no longer qualifies" do
    kase = create(:clinical_case, verification_verdict: "supported", status: "published")
    kase.update_column(:verification_verdict, "unsupported")

    expect(described_class.call.payload).to include(withdrawn: 1, live: 0)
    expect(kase.reload).to be_status_draft
  end
end

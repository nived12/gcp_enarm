require "rails_helper"

RSpec.describe ClinicalCase do
  describe "#publishable?" do
    it "is true only once a verifier has called it supported" do
      expect(build(:clinical_case, verification_verdict: "supported")).to be_publishable
    end

    it "is false while no verifier has looked at it — silence is not assent" do
      expect(build(:clinical_case, verification_verdict: nil)).not_to be_publishable
    end

    it "is false when the verifier was unsure" do
      expect(build(:clinical_case, verification_verdict: "ambiguous")).not_to be_publishable
    end

    it "is false when the verifier disagreed" do
      expect(build(:clinical_case, verification_verdict: "unsupported")).not_to be_publishable
    end

    it "is false once a person has withdrawn it, even if supported" do
      expect(build(:clinical_case, verification_verdict: "supported", status: "retired")).not_to be_publishable
      expect(build(:clinical_case, verification_verdict: "supported", status: "flagged")).not_to be_publishable
    end
  end

  describe ".publishable" do
    it "returns only the supported cases nobody has withdrawn" do
      supported = create(:clinical_case, verification_verdict: "supported")
      create(:clinical_case, verification_verdict: "supported", status: "retired")
      create(:clinical_case, verification_verdict: "unsupported")
      create(:clinical_case, verification_verdict: nil)

      expect(described_class.publishable).to contain_exactly(supported)
    end
  end

  it "refuses to be published without a supported verdict" do
    kase = build(:clinical_case, verification_verdict: "ambiguous", status: "published")

    expect(kase).not_to be_valid
    expect(kase.errors.of_kind?(:status, :not_supported)).to be(true)
  end

  it "uses the exam's own difficulty vocabulary" do
    expect(described_class.difficulties.keys).to eq(%w[low medium high])
  end

  it "destroys its questions with it" do
    question = create(:question)

    expect { question.clinical_case.destroy }.to change(described_class.all, :count).by(-1)
    expect(Question.exists?(question.id)).to be(false)
  end
end

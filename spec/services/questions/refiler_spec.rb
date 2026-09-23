require "rails_helper"

RSpec.describe Questions::Refiler do
  let(:guideline) { create(:guideline) }

  it "moves a case to its guideline's current main topic and that topic's specialty" do
    kase = create(:clinical_case, guideline: guideline, topic: create(:topic))
    topic = create(:guideline_topic, guideline: guideline).topic

    expect(described_class.call.payload).to eq(moved: 1)
    expect(kase.reload).to have_attributes(topic: topic, specialty: topic.branch.specialty)
  end

  it "leaves a case that is already filed right" do
    topic = create(:guideline_topic, guideline: guideline).topic
    create(:clinical_case, guideline: guideline, topic: topic, specialty: topic.branch.specialty)

    expect(described_class.call.payload).to eq(moved: 0)
  end

  it "clears the topic when the guideline no longer names one" do
    kase = create(:clinical_case, guideline: guideline, topic: create(:topic))

    described_class.call

    expect(kase.reload).to have_attributes(topic: nil, specialty: nil)
  end
end

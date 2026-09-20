require "rails_helper"

RSpec.describe Gpc::IngestGuidelineJob do
  let(:guideline) { create(:guideline, external_id: "4081") }
  let(:sections) { [attributes_for(:guideline_section).merge(position: 1)] }

  def fetcher_returns(response)
    allow(Gpc::LiveGuidelineFetcher).to receive(:call).and_return(response)
  end

  it "runs on the queue reserved for the live site" do
    expect(described_class.new.queue_name).to eq("ingestion")
  end

  it "imports what the fetcher returns" do
    fetcher_returns(Gpc::LiveGuidelineFetcher.new(guideline).success(sections))

    expect { described_class.perform_now(guideline) }.to change(GuidelineSection, :count).by(1)
  end

  it "imports nothing when the site could not be read" do
    fetcher_returns(Gpc::LiveGuidelineFetcher.new(guideline).failure("El sitio respondió 503"))

    expect { described_class.perform_now(guideline) }.not_to change(GuidelineSection, :count)
  end
end

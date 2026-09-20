require "rails_helper"

RSpec.describe Gpc::RefreshCatalogJob do
  let(:entries) do
    [{ catalog_key: "SS-757-25", title: "Infección por Chikungunya", institution: "health_ministry",
       year: 2025, source: "live_site", external_id: "4081", specialty_labels: [], levels_of_care: [] }]
  end

  def fetcher_returns(response)
    allow(Gpc::LiveCatalogFetcher).to receive(:call).and_return(response)
  end

  def success_with(payload) = Gpc::LiveCatalogFetcher.new.success(payload)
  def failure_with(message) = Gpc::LiveCatalogFetcher.new.failure(message)

  it "runs on the single-threaded ingestion queue" do
    expect(described_class.new.queue_name).to eq("ingestion")
  end

  it "picks up a guideline the catalog has gained since the last run" do
    fetcher_returns(success_with(entries))

    expect { described_class.perform_now }.to change(Guideline, :count).by(1)
  end

  # The catalog row carries the title and year; it says nothing about the recommendations
  # inside, so every guideline is re-read rather than only the ones whose row changed.
  it "queues a re-read of every live guideline, not only the changed ones" do
    unchanged = create(:guideline, source: "live_site")
    create(:guideline, source: "web_archive")
    fetcher_returns(success_with(entries))

    expect { described_class.perform_now }
      .to have_enqueued_job(Gpc::IngestGuidelineJob).twice

    expect(Gpc::IngestGuidelineJob).to have_been_enqueued.with(unchanged)
  end

  it "leaves the archive alone, because those captures are history" do
    archived = create(:guideline, source: "web_archive")
    fetcher_returns(success_with(entries))

    described_class.perform_now

    expect(Gpc::IngestGuidelineJob).not_to have_been_enqueued.with(archived)
  end

  it "does nothing when the site is unreachable, rather than half-updating" do
    fetcher_returns(failure_with("El catálogo respondió 503"))

    expect { described_class.perform_now }.not_to change(Guideline, :count)
    expect(Gpc::IngestGuidelineJob).not_to have_been_enqueued
  end

  it "stops when the catalog cannot be saved" do
    fetcher_returns(success_with([entries.first.merge(institution: nil)]))

    expect { described_class.perform_now }.not_to change(Guideline, :count)
    expect(Gpc::IngestGuidelineJob).not_to have_been_enqueued
  end
end

require "rails_helper"

RSpec.describe Gpc::IngestArchivedGuidelineJob do
  let(:entry) { { catalog_key: "IMSS-051-18", document_url: "https://web.archive.org/web/1id_/x.pdf" } }

  # Same queue as the live-site jobs: a different server, the same courtesy, and the
  # whole ingestion stays serial and restartable.
  it "runs on the queue reserved for ingestion" do
    expect(described_class.new.queue_name).to eq("ingestion")
  end

  it "hands the entry to the importer" do
    allow(Gpc::ArchiveGuidelineImporter).to receive(:call)

    described_class.perform_now(entry)

    expect(Gpc::ArchiveGuidelineImporter).to have_received(:call).with(entry)
  end
end

require "rails_helper"

RSpec.describe Gpc::ArchiveCatalogFetcher do
  # Real CDX rows, trimmed: the two spellings of a catalog key, the legacy S- prefix,
  # and the four kinds of row that must not become guidelines.
  let(:index) { file_fixture("gpc/archive_index.json").read }
  let(:cdx_url) { %r{https://web\.archive\.org/cdx/search/cdx} }

  def stub_index(status: 200, body: nil)
    stub_request(:get, cdx_url).to_return(status: status, body: body || index)
  end

  describe "a successful fetch" do
    before { stub_index }

    it "returns one entry per archived summary" do
      response = described_class.call

      expect(response).to be_success
      expect(response.payload.map { |e| e[:catalog_key] }).to eq(["IMSS-051-18", "S-102-08", "IMSS-028-22"])
    end

    it "treats the GPC- prefix as decoration, not part of the key" do
      expect(described_class.call.payload.first[:catalog_key]).to eq("IMSS-051-18")
    end

    it "reads the institution through the legacy S- spelling" do
      entry = described_class.call.payload.find { |e| e[:catalog_key] == "S-102-08" }

      expect(entry).to include(institution: "health_ministry", year: 2008, source: "web_archive")
    end

    it "asks for the bytes as captured, not the archive's rewritten copy" do
      entry = described_class.call.payload.first

      expect(entry[:document_url]).to eq(
        "https://web.archive.org/web/20211208182334id_/" \
        "http://www.cenetec-difusion.com/CMGPC/GPC-IMSS-051-18/ER.pdf"
      )
    end

    it "keeps the capture timestamp, which is what makes a re-run free" do
      expect(described_class.call.payload.first[:external_id]).to eq("20211208182334")
    end
  end

  describe "rows that are not a guideline summary" do
    before { stub_index }

    it "skips the full reference guide and keeps only the summary" do
      expect(described_class.call.payload.count { |e| e[:catalog_key] == "IMSS-051-18" }).to eq(1)
    end

    it "skips a capture the archive answered with its own error page" do
      expect(described_class.call.payload.map { |e| e[:catalog_key] }).not_to include("DIF-332-09")
    end

    it "skips a capture that was not 200" do
      expect(described_class.call.payload.map { |e| e[:catalog_key] }).not_to include("DIF-565-12")
    end

    it "skips a key that fits neither spelling rather than guessing at it" do
      expect(described_class.call.payload.map { |e| e[:catalog_key] }).not_to include("DIF-25709")
    end
  end

  describe "when the archive does not cooperate" do
    it "fails when the index is throttled" do
      stub_index(status: 503)

      expect(described_class.call.errors.full_messages.first).to include("503")
    end

    it "fails when the index holds no guideline" do
      stub_index(body: '[["original","timestamp","statuscode","mimetype"]]')

      expect(described_class.call.errors.full_messages.first).to include("no devolvió ninguna guía")
    end

    it "fails when the index is not JSON" do
      stub_index(body: "<html>Temporarily Offline</html>")

      expect(described_class.call.errors.full_messages.first).to include("no devolvió JSON")
    end

    it "fails when the index is an empty list rather than rows" do
      stub_index(body: "[]")

      expect(described_class.call.errors.full_messages.first).to include("no devolvió ninguna guía")
    end

    it "fails when the index comes back empty" do
      stub_index(body: "")

      expect(described_class.call).not_to be_success
    end

    # The archive resets connections mid-run. An ingestion that raises here has thrown
    # away every guideline it already fetched.
    it "records a reset connection as a failure instead of raising" do
      stub_request(:get, cdx_url).to_raise(Errno::ECONNRESET)

      expect(described_class.call.errors.full_messages.first).to include("ECONNRESET")
    end
  end
end

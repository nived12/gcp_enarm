require "rails_helper"

RSpec.describe Gpc::ArchiveGuidelineImporter do
  let(:pdf) { file_fixture("gpc/archived_guideline.pdf").binread }
  let(:url) { "https://web.archive.org/web/20211208182334id_/http://example.test/ER.pdf" }
  let(:entry) do
    { catalog_key: "IMSS-051-18", institution: "imss", year: 2018, source: "web_archive",
      external_id: "20211208182334", catalog_url: "https://web.archive.org/web/20211208182334/x",
      document_url: url }
  end

  def stub_pdf(body: nil) = stub_request(:get, url).to_return(status: 200, body: body || pdf)

  # The fetcher waits between retries because the archive throttles. Nothing here is
  # testing that wait, and paying for it would add twenty seconds to the suite.
  before { allow_any_instance_of(Gpc::ArchivePdfFetcher).to receive(:sleep) }

  describe "importing" do
    before { stub_pdf }

    it "creates the guideline, naming it from inside the PDF" do
      response = described_class.call(entry)

      expect(response).to be_success
      expect(Guideline.sole).to have_attributes(
        catalog_key: "IMSS-051-18", source: "web_archive", institution: "imss", year: 2018,
        title: "Tratamiento quirurgico de la obesidad en el adulto"
      )
    end

    it "stores the extracted text as the guideline's one section" do
      described_class.call(entry)

      section = Guideline.sole.guideline_sections.sole

      expect(section).to have_attributes(kind: "archived_document", external_id: "20211208182334")
      expect(section.body).to include("riesgo quirurgico")
    end

    # A PDF whose header never extracted still has its key, which is how a student cites it.
    it "falls back to the catalog key when the PDF will not give up a title" do
      allow(Gpc::DocumentTitle).to receive(:call).and_return(described_class.new(entry).failure("sin título"))

      described_class.call(entry)

      expect(Guideline.sole.title).to eq("IMSS-051-18")
    end
  end

  describe "work it declines to redo" do
    it "leaves a guideline the live site still publishes alone" do
      live = create(:guideline, catalog_key: "IMSS-051-18", source: "live_site", title: "La versión viva")

      expect(described_class.call(entry).payload).to eq(skipped: :published_live)
      expect(live.reload.title).to eq("La versión viva")
      expect(WebMock).not_to have_requested(:get, url)
    end

    # The capture timestamp means the same bytes, so a re-run must not spend another
    # megabyte on a rate-limited archive. This is what makes an interrupted run resumable.
    it "skips a capture it already holds, without downloading it again" do
      stub_pdf
      described_class.call(entry)
      WebMock.reset_executed_requests!

      expect(described_class.call(entry).payload).to eq(skipped: :already_imported)
      expect(WebMock).not_to have_requested(:get, url)
    end

    it "re-imports when the archive offers a newer capture" do
      stub_pdf
      described_class.call(entry)
      newer = entry.merge(external_id: "20240101000000")
      stub_request(:get, newer[:document_url]).to_return(status: 200, body: pdf)

      described_class.call(newer)

      expect(Guideline.sole.guideline_sections.pluck(:external_id))
        .to contain_exactly("20211208182334", "20240101000000")
    end
  end

  describe "failures" do
    it "fails without writing when the PDF cannot be fetched" do
      stub_request(:get, url).to_return(status: 503)

      expect(described_class.call(entry)).not_to be_success
      expect(Guideline.count).to eq(0)
    end

    # Header and end marker both present, so the fetcher accepts it; there is no
    # readable document between them.
    it "fails without writing when the bytes are a PDF only on the outside" do
      stub_pdf(body: "%PDF-1.4\nbasura\n%%EOF\n")

      expect(described_class.call(entry)).not_to be_success
      expect(Guideline.count).to eq(0)
    end

    it "fails when the entry would make an invalid guideline" do
      stub_pdf

      expect(described_class.call(entry.merge(institution: nil))).not_to be_success
    end
  end
end

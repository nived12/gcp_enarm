require "rails_helper"

RSpec.describe Gpc::ArchivePdfFetcher do
  let(:url) { "https://web.archive.org/web/20211208182334id_/http://example.test/ER.pdf" }
  let(:pdf) { file_fixture("gpc/archived_guideline.pdf").binread }

  # The pause between attempts is politeness towards a throttled archive, not behaviour
  # under test.
  def fetch = described_class.call(url, retry_interval: 0)

  it "returns the bytes as captured" do
    stub_request(:get, url).to_return(status: 200, body: pdf)

    response = fetch

    expect(response).to be_success
    expect(response.payload).to start_with("%PDF")
    expect(response.payload.bytesize).to eq(pdf.bytesize)
  end

  describe "downloads that arrive wrong" do
    # The archive answers a throttled capture with an HTML page and a 200.
    it "fails when the archive serves a page instead of the PDF" do
      stub_request(:get, url).to_return(status: 200, body: "<html>Too Many Requests</html>")

      expect(fetch.errors.full_messages.first).to include("no es un PDF")
    end

    # Under load it instead answers 200 with a convincing PDF that simply stops: the
    # right header, a plausible Content-Length, and no end marker.
    it "fails when the PDF stops before its end marker" do
      stub_request(:get, url).to_return(status: 200, body: pdf.byteslice(0, 800))

      expect(fetch.errors.full_messages.first).to include("llegó incompleto")
    end

    it "accepts a PDF shorter than the window it looks for the end marker in" do
      expect(pdf.bytesize).to be < described_class::TRAILER_WINDOW

      stub_request(:get, url).to_return(status: 200, body: pdf)

      expect(fetch).to be_success
    end
  end

  describe "retrying" do
    it "takes a complete download after a truncated one" do
      stub_request(:get, url)
        .to_return({ status: 200, body: pdf.byteslice(0, 800) }, { status: 200, body: pdf })

      expect(fetch).to be_success
    end

    it "retries a throttled response" do
      stub_request(:get, url).to_return({ status: 503 }, { status: 200, body: pdf })

      expect(fetch).to be_success
    end

    it "gives up after a bounded number of attempts rather than hammering the archive" do
      stub_request(:get, url).to_return(status: 503)

      expect(fetch).not_to be_success
      expect(a_request(:get, url)).to have_been_made.times(described_class::ATTEMPTS)
    end

    # Each attempt starts clean, so a run of failures does not report the first one three
    # times over.
    it "reports one error, not one per attempt" do
      stub_request(:get, url).to_return(status: 503)

      expect(fetch.errors.size).to eq(1)
    end

    it "records a reset connection as a failure instead of raising" do
      stub_request(:get, url).to_raise(Errno::ECONNRESET)

      expect(fetch).not_to be_success
    end
  end
end

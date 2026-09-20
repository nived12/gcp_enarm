require "rails_helper"

RSpec.describe Gpc::ArchivePdfFetcher do
  let(:url) { "https://web.archive.org/web/20211208182334id_/http://example.test/ER.pdf" }
  let(:pdf) { file_fixture("gpc/archived_guideline.pdf").binread }

  it "returns the bytes as captured" do
    stub_request(:get, url).to_return(status: 200, body: pdf)

    response = described_class.call(url)

    expect(response).to be_success
    expect(response.payload).to start_with("%PDF")
  end

  # The archive answers a throttled or missing capture with an HTML page and a 200, so
  # the bytes themselves have to say what they are.
  it "fails when the archive serves a page instead of the PDF" do
    stub_request(:get, url).to_return(status: 200, body: "<html>Too Many Requests</html>")

    expect(described_class.call(url).errors.full_messages.first).to include("no es un PDF")
  end

  it "fails when the archive is down" do
    stub_request(:get, url).to_return(status: 503)

    expect(described_class.call(url).errors.full_messages.first).to include("503")
  end

  it "records a reset connection as a failure instead of raising" do
    stub_request(:get, url).to_raise(Errno::ECONNRESET)

    expect(described_class.call(url)).not_to be_success
  end
end

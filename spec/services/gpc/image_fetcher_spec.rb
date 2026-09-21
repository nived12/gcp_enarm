require "rails_helper"

RSpec.describe Gpc::ImageFetcher do
  let(:path) { "imagenes/doc_4081/cuadro_2.jpg" }
  let(:url) { "https://gpc.salud.gob.mx/DDIMBE/#{path}" }
  let(:bytes) { file_fixture("gpc/figure.png").binread }

  it "returns the bytes with a content type taken from the extension" do
    stub_request(:get, url).to_return(status: 200, body: bytes)

    result = described_class.call(path)

    expect(result).to be_success
    expect(result.payload).to include(filename: "cuadro_2.jpg", content_type: "image/jpeg")
    expect(result.payload[:bytes].bytesize).to eq(bytes.bytesize)
  end

  it "falls back to a generic type for an extension it does not know" do
    stub_request(:get, "https://gpc.salud.gob.mx/DDIMBE/a/figura.tif").to_return(body: bytes)

    expect(described_class.call("a/figura.tif").payload[:content_type])
      .to eq("application/octet-stream")
  end

  it "reports the path when the site refuses" do
    stub_request(:get, url).to_return(status: 404)

    expect(described_class.call(path).errors.full_messages.first).to include(path)
  end

  # A 200 with nothing in it is how this site answers for a file it has lost, and an
  # empty attachment is worse than none: it looks present everywhere downstream.
  it "refuses an empty body even though the request succeeded" do
    stub_request(:get, url).to_return(status: 200, body: "")

    expect(described_class.call(path).errors.full_messages.first).to include("llegó vacía")
  end
end

require "rails_helper"

RSpec.describe Gpc::PdfExtractor do
  # A two-page PDF built to the same template shape as a real archived guideline: the
  # catalog key, the running header under it, the publisher block. The real ones are
  # 1–2 MB each, which is no size for a fixture.
  let(:bytes) { file_fixture("gpc/archived_guideline.pdf").binread }

  it "returns the text of every page" do
    response = described_class.call(bytes)

    expect(response).to be_success
    expect(response.payload[:page_count]).to eq(2)
    expect(response.payload[:text]).to include("se sugiere valorar el riesgo quirurgico")
  end

  it "names the document from its running header" do
    expect(described_class.call(bytes).payload[:title])
      .to eq("Tratamiento quirurgico de la obesidad en el adulto")
  end

  it "returns a nil title rather than failing when no line reads as one" do
    allow(Gpc::DocumentTitle).to receive(:call).and_return(described_class.new("").failure("sin título"))

    response = described_class.call(bytes)

    expect(response).to be_success
    expect(response.payload[:title]).to be_nil
  end

  it "fails on bytes that are not a PDF" do
    response = described_class.call("no soy un PDF")

    expect(response).not_to be_success
    expect(response.errors.full_messages.first).to include("No se pudo leer el PDF")
  end

  it "fails on a PDF with no text layer" do
    allow(PDF::Reader).to receive(:new).and_return(instance_double(PDF::Reader, pages: [double(text: "")]))

    expect(described_class.call(bytes).errors.full_messages.first).to include("no contiene texto")
  end
end

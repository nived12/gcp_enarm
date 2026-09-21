require "rails_helper"

RSpec.describe Gpc::ImageIngester do
  let(:guideline) { create(:guideline, catalog_key: "SS-219-24", year: 2024, title: "Insuficiencia cardiaca") }
  let(:url) { "https://gpc.salud.gob.mx/DDIMBE/imagenes/doc_4081/cuadro_2.jpg" }

  def build_section(heading: "CUADRO 2", body: nil)
    create(
      :guideline_section, guideline: guideline, heading: heading,
      body: body || '<img src="~imagenes/doc_4081/cuadro_2.jpg">CUADRO 2 MARCADORES DE CONGESTIÓN'
    )
  end

  def ingest = described_class.call(GuidelineSection.all, interval: 0)

  before { stub_request(:get, url).to_return(status: 200, body: file_fixture("gpc/figure.png").binread) }

  it "stores the figure and downloads its file" do
    build_section

    expect(ingest.payload).to include(created: 1, downloaded: 1)

    image = ClinicalImage.sole
    expect(image).to have_attributes(label: "CUADRO 2", kind: "table", position: 1)
    expect(image.file).to be_attached
  end

  # The licence asks the source to travel with the figure, so it is written onto the row
  # at ingest rather than assembled by whichever view renders it.
  it "writes the attribution from the guideline it came from" do
    build_section

    ingest

    expect(ClinicalImage.sole.attribution).to eq("GPC SS-219-24 · Insuficiencia cardiaca · 2024")
  end

  it "does not download a file it already has, so a half-finished run can be re-run" do
    build_section
    ingest

    expect(ingest.payload).to include(updated: 1, already_stored: 1)
    expect(WebMock).to have_requested(:get, url).once
  end

  it "rebuilds metadata without touching the network when asked not to download" do
    build_section

    expect(described_class.call(GuidelineSection.all, download: false).payload).to include(created: 1)
    expect(ClinicalImage.sole.file).not_to be_attached
    expect(WebMock).not_to have_requested(:get, url)
  end

  # One missing file is not a reason to abandon 900 others.
  it "counts a failed download and carries on" do
    stub_request(:get, url).to_return(status: 500)
    build_section

    expect(ingest.payload).to include(created: 1, failed: 1)
    expect(ClinicalImage.sole.file).not_to be_attached
  end

  it "skips a section whose images are the guideline's working papers" do
    build_section(heading: "CUADRO 4", body: '<img src="~a/cuadro_de_evidencia_4.jpg">')

    expect(ingest.payload).to be_empty
    expect(ClinicalImage.count).to eq(0)
  end

  # The filter separates medicine from the guideline's working papers and has been wrong
  # twice already, so a re-run has to take rows away as well as add them.
  it "removes a figure the filter no longer accepts" do
    section = build_section
    ingest
    section.update!(body: '<h2>ESCALA GRADE</h2><img src="~a/escala_1.jpg">', heading: "ESCALA 1")

    expect(ingest.payload).to include(removed: 1)
    expect(ClinicalImage.count).to eq(0)
  end

  it "leaves a case that pointed at a removed figure without one, rather than broken" do
    section = build_section
    ingest
    kase = create(:clinical_case, clinical_image: ClinicalImage.sole)
    section.update!(body: "<p>ya no hay figura</p>")

    ingest

    expect(kase.reload.clinical_image).to be_nil
  end
end

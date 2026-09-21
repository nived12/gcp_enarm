require "rails_helper"

RSpec.describe Gpc::ImageParser do
  def section(heading:, body:)
    build(:guideline_section, heading: heading, body: body)
  end

  def parse(...) = described_class.call(section(...)).payload

  it "reads the figure a section publishes, with the caption the guideline gave it" do
    rows = parse(
      heading: "CUADRO 2",
      body: '<img src="~imagenes/doc_4081/cuadro_2.jpg" alt="cuadro_2">CUADRO 2 MARCADORES DE CONGESTIÓN'
    )

    expect(rows.sole).to include(
      label: "CUADRO 2", caption: "MARCADORES DE CONGESTIÓN",
      kind: "table", position: 1, remote_path: "imagenes/doc_4081/cuadro_2.jpg"
    )
  end

  it "numbers a figure the site split across several files" do
    rows = parse(
      heading: "CUADRO 6",
      body: '<img src="~imagenes/doc_3033/cuadro_6_1.jpg"><img src="~imagenes/doc_3033/cuadro_6_2.jpg">'
    )

    expect(rows.map { |row| row[:position] }).to eq([1, 2])
  end

  it "names the kind from the heading, because nothing else says what a figure is" do
    expect(parse(heading: "ALGORITMO 1", body: '<img src="~a/algoritmo_1.jpg">').sole[:kind])
      .to eq("algorithm")
    expect(parse(heading: "ESCALA DE GLASGOW", body: '<img src="~a/escala_1.jpg">').sole[:kind])
      .to eq("scale")
    expect(parse(heading: "FIGURA 3", body: '<img src="~a/figura_3.jpg">').sole[:kind])
      .to eq("figure")
  end

  # The heading alone cannot tell these apart: the GRADE appraisal of a recommendation is
  # published under "CUADRO 4" exactly like the criteria table is.
  it "drops the guideline's working papers, which are filed as figures too" do
    rows = parse(
      heading: "CUADRO 4",
      body: '<img src="~a/cuadro_4.jpg"><img src="~a/cuadro_de_evidencia_4.jpg">' \
            '<img src="~a/escala_grade_1.jpg"><img src="~a/escala_sign_2.jpg">'
    )

    expect(rows.map { |row| row[:remote_path] }).to eq(["a/cuadro_4.jpg"])
  end

  it "ignores a section that is not publishing a figure at all" do
    expect(parse(heading: "GRUPO DE DESARROLLO", body: '<img src="~a/gp_1.jpg">')).to be_empty
    expect(parse(heading: "BUSQUEDA DE GPC", body: '<img src="~a/protocolo_1.jpg">')).to be_empty
  end

  it "leaves the caption empty when the section says nothing beyond its own heading" do
    expect(parse(heading: "FIGURA 9", body: '<img src="~a/figura_9.jpg">FIGURA 9').sole[:caption])
      .to be_nil
  end

  it "ignores an image tag with no source" do
    expect(parse(heading: "CUADRO 1", body: "<img alt='vacío'>")).to be_empty
  end

  it "returns nothing for a section with no images" do
    expect(parse(heading: "CUADRO 1", body: "<p>Sólo texto</p>")).to be_empty
  end

  # 590 of the 622 sections that publish a figure put its caption in an <h2>; the rest
  # lead with it as plain text.
  it "prefers the caption the site marked up as one" do
    rows = parse(
      heading: "CUADRO 1",
      body: "<h2>CRITERIOS DIAGNÓSTICOS</h2><img src=\"~a/cuadro_1.jpg\"><p>Requerimientos: bolígrafo</p>"
    )

    expect(rows.sole[:caption]).to eq("CRITERIOS DIAGNÓSTICOS")
  end

  # One guideline publishes a whole PHQ-9 instruction sheet in the section body, and an
  # unbounded caption goes straight into the generation prompt.
  it "keeps a caption to caption length" do
    rows = parse(heading: "CUADRO 1", body: "<img src=\"~a/cuadro_1.jpg\">#{"palabra " * 80}")

    expect(rows.sole[:caption].length).to be <= described_class::CAPTION_LIMIT
  end

  # The filename is innocent — escala_1.jpg under "ESCALA 1" — so only what the figure
  # calls itself gives it away. 72 of these were kept before the caption was consulted.
  it "drops a grading scale that the filename could not give away" do
    expect(parse(heading: "ESCALA 1", body: '<h2>ESCALA GRADE</h2><img src="~a/escala_1.jpg">')).to be_empty
    expect(parse(heading: "CUADRO 3", body: '<h2>NIVELES DE EVIDENCIA</h2><img src="~a/cuadro_3.jpg">')).to be_empty
  end

  it "keeps a clinical scale, which is what those headings usually mean" do
    rows = parse(heading: "ESCALA 2", body: '<h2>ESCALA DE GLASGOW</h2><img src="~a/escala_2.jpg">')

    expect(rows.sole).to include(caption: "ESCALA DE GLASGOW", kind: "scale")
  end
end

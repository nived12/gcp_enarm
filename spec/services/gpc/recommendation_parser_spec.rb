require "rails_helper"

RSpec.describe Gpc::RecommendationParser do
  # Grading strips copied verbatim from across the live catalog — no one guideline
  # spells them every way the authors do.
  let(:body) { file_fixture("gpc/section_grading_variants.html").read }
  let(:statements) { described_class.call(body).payload }

  def statement(grade)
    statements.find { |s| s[:grade] == grade }
  end

  it "returns one statement per separador that is followed by text" do
    expect(statements.size).to eq(11)
  end

  it "numbers statements in document order" do
    expect(statements.map { |s| s[:position] }).to eq((1..11).to_a)
  end

  it "keeps the strip verbatim in label" do
    expect(statements.map { |s| s[:label] }).to include("A NICE Hong K, 2021", "PBP")
  end

  it "splits a strip written grade-scale-citation" do
    expect(statement("A")).to include(scale: "NICE", citation: "Hong K, 2021")
  end

  it "reads a compound evidence level as one grade" do
    expect(statement("1++")).to include(scale: "NICE", citation: "Carter E, 2017")
  end

  it "reads a grade written as words" do
    expect(statement("Muy baja")).to include(scale: "GRADE", citation: "Dhatariya KK, 2020")
  end

  it "leaves the citation nil when the strip names no study" do
    expect(statement("Fuerte a favor")).to include(scale: "GRADE", citation: nil)
  end

  it "reads a grade that follows its scale" do
    expect(statement("D")).to include(scale: "SIGN", citation: "Taylor M, 2015")
  end

  it "matches the longest scale name, not a fragment of it" do
    expect(statement("IIa")).to include(scale: "ACC/AHA/ESC", citation: "Thygesen K, 2018")
  end

  # Recognising the scale by shape rather than by name means a society we have never
  # seen — or, here, one the authors misspelled — still yields a citation.
  it "reads a scale it has no list entry for" do
    misspelled = statements.find { |s| s[:label] == "FUERTE SHRE 2022" }

    expect(misspelled).to include(grade: "FUERTE", scale: "SHRE", citation: "2022")
  end

  # A recommendation class in Roman numerals is three capitals and would otherwise
  # pass for a scale acronym, stranding the real scale inside the citation.
  it "does not read a recommendation class as the scale" do
    expect(statement("IIA")).to include(scale: "ACC/AHA", citation: "Powers W, 2019")
  end

  it "drops the label word some guidelines put before the scale" do
    expect(statement("III")).to include(scale: "ESCMID", citation: "Krishnasami Z, 2002")
  end

  it "leaves grade, scale and citation nil when the strip names no scale at all" do
    unparsed = statements.find { |s| s[:label] == "Condicional a favor" }

    expect(unparsed).to include(grade: nil, scale: nil, citation: nil)
    expect(unparsed[:text]).to start_with("Se sugiere individualizar")
  end

  it "does not mistake a good-practice marker for a scale" do
    marker = statements.find { |s| s[:label] == "PBP" }

    expect(marker).to include(grade: nil, scale: nil, citation: nil)
    expect(marker[:text]).to start_with("Se sugiere vigilar")
  end

  it "drops a separador with nothing after it" do
    expect(statements.map { |s| s[:label] }).not_to include("B NICE Sin texto")
  end

  it "collects list items that continue a statement, one per line" do
    expect(statement("1++")[:text].lines.map(&:chomp)).to eq(
      ["Los aspectos esenciales de un programa de educación perinatal son:",
       "Trabajo de parto y parto normal",
       "Cuidados del recién nacido"]
    )
  end

  it "returns nothing for a section with no grading strips" do
    expect(described_class.call("<h2>OBJETIVOS</h2><p>Texto.</p>").payload).to be_empty
  end

  # SS-757-25 as published: a RECOMENDACIONES section whose authors found no evidence
  # to grade, so it carries prose and no strips. Nothing to cite is the right answer —
  # the prose stays on GuidelineSection#body.
  it "returns nothing for a recommendations section the authors could not grade" do
    body = file_fixture("gpc/section_36780.html").read

    expect(Nokogiri::HTML.fragment(body).text).to include("no encontró evidencia suficiente")
    expect(described_class.call(body).payload).to be_empty
  end
end

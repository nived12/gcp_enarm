require "rails_helper"

# The label shapes below are the ones the archive actually prints in its grading column.
RSpec.describe Gpc::ArchiveTable::GradingLabel do
  def parse(label, kind = "evidence") = described_class.parse(label, kind)

  it "reads a Shekelle grade with the scale's own year in brackets" do
    expect(parse("III (Shekelle,1999) Humes, 2008")).to eq(grade: "III", scale: "Shekelle", citation: "Humes, 2008")
    expect(parse("Ia [E: Shekelle] Matheson, 2007")).to eq(grade: "Ia", scale: "Shekelle", citation: "Matheson, 2007")
  end

  it "reads a two-word grade and a scale named by its acronym" do
    expect(parse("Muy baja GRADE Lee, 2018")).to eq(grade: "Muy baja", scale: "GRADE", citation: "Lee, 2018")
    expect(parse("ALTO GRADE Turc G, 2019")).to eq(grade: "ALTO", scale: "GRADE", citation: "Turc G, 2019")
  end

  it "skips the word that names a grade" do
    expect(parse("Nivel 3 NICE Smith, 2010")).to eq(grade: "3", scale: "NICE", citation: "Smith, 2010")
  end

  it "reads evidence drawn as GRADE's circles" do
    expect(parse("⊕⊕◯◯ GRADE Ortiz, 2015")).to include(grade: "⊕⊕◯◯", scale: "GRADE")
  end

  # A lone letter is also an author's initial, so it only counts straight after the year.
  it "finds a grade the row cut left behind the citation" do
    expect(parse("Smith J, 2010 B")).to eq(grade: "B", scale: nil, citation: "Smith J, 2010")
  end

  it "reads a good-practice point as PBP" do
    expect(parse("Punto de Buena Práctica", "good_practice")).to eq(grade: "PBP", scale: nil, citation: nil)
  end
end

require "rails_helper"

RSpec.describe Gpc::ArchiveSectionBuilder do
  let(:table) { file_fixture("gpc/archived_evidence_table.txt").read }
  let(:guideline) { create(:guideline, catalog_key: "IMSS-031-08", source: "web_archive", year: 2009) }
  let(:document) do
    create(
      :guideline_section, guideline: guideline, kind: "archived_document", external_id: "20090101",
      heading: "RESUMEN DE EVIDENCIAS Y RECOMENDACIONES", position: 1, body: table
    )
  end

  # Every word known, so the headings are read as the fixture has them; the damaged-heading
  # example below says otherwise.
  let(:headings) { Gpc::HeadingCleaner.new(Hash.new(Gpc::HeadingCleaner::MIN_COUNT)) }

  def build = described_class.call(document, headings: headings)
  def derived = document.derived_sections.order(:position)

  def section(external_id) = derived.find_by!(external_id: "20090101/#{external_id}")

  it "files the table's statements as sections per numbered heading and kind" do
    result = build

    expect(result).to be_success
    expect(result.payload).to eq(sections: 5, rebuilt: 5, recommendations: 15)
    expect(derived.pluck(:kind)).to eq(%w[evidence recommendation evidence recommendation good_practice])
    expect(derived.pluck(:position)).to eq([2, 3, 4, 5, 6])
  end

  it "reads each section the way a live one reads" do
    build

    diagnosis = section("4-2-1-1-diagnostico-clinico-y-paraclinico-en-el-adulto-joven-recommendation")

    expect(diagnosis).to have_attributes(heading: "RECOMENDACIONES", kind: "recommendation", guideline: guideline)
    expect(diagnosis.menu_path).to eq(
      "4.2 Diagnostico › 4.2.1.1 Diagnóstico Clínico Y Paraclínico En El Adulto Joven › RECOMENDACIONES"
    )
    expect(diagnosis.recommendations.first).to have_attributes(
      position: 1, grade: "D", scale: "Shekelle", citation: "Humes, 2008", label: "D (Shekelle,1999) Humes, 2008"
    )
    expect(Recommendation.actionable.count).to eq(8)
  end

  it "leaves out a heading extraction damaged, keeping the section" do
    described_class.call(document, headings: Gpc::HeadingCleaner.new(Hash.new(0)))

    diagnosis = section("4-2-1-1-diagnostico-clinico-y-paraclinico-en-el-adulto-joven-recommendation")
    expect(diagnosis.menu_path).to eq("4.2 Diagnostico › RECOMENDACIONES")
    expect(diagnosis.recommendations.count).to be_positive
  end

  it "reads its vocabulary from the corpus when none is handed to it" do
    expect(described_class.call(document)).to be_success
  end

  it "leaves every section alone when nothing changed" do
    build
    ids = derived.pluck(:id)

    expect(build.payload).to include(rebuilt: 0)
    expect(derived.pluck(:id)).to eq(ids)
  end

  it "rebuilds only the section whose statements changed, and drops the one that vanished" do
    build
    evidence = section("4-2-1-1-diagnostico-clinico-y-paraclinico-en-el-adulto-joven-evidence")
    document.update!(body: table.sub(/^\/R.*?ginecoobstetricia\.\n/m, ""))

    result = build

    expect(result.payload).to include(sections: 4, rebuilt: 0)
    expect(derived.pluck(:kind)).not_to include("good_practice")
    expect(evidence.reload.recommendations.count).to eq(6)
  end

  it "keeps the row of a statement whose text survived, so its question keeps its citation" do
    build
    evidence = section("4-2-1-1-diagnostico-clinico-y-paraclinico-en-el-adulto-joven-evidence")
    cited = evidence.recommendations.find_by!(position: 4)
    question = create(:question, recommendation: cited)
    document.update!(body: table.sub(/^ +E +En estudios de laboratorio.*?bandemia\..*?\n/m, ""))

    expect(build).to be_success
    expect(evidence.recommendations.count).to eq(5)
    expect(question.reload.recommendation).to eq(cited)
    expect(cited.reload.position).to eq(3)
  end

  # A survivor whose place did not change used to look unchanged, was never saved, and
  # stayed parked below zero; a later rebuild flipped it back on top of another row.
  it "leaves every survivor at its real position" do
    build
    evidence = section("4-2-1-1-diagnostico-clinico-y-paraclinico-en-el-adulto-joven-evidence")
    document.update!(body: table.sub(/^ +E +En estudios de laboratorio.*?bandemia\..*?\n/m, ""))

    expect(build).to be_success
    expect(evidence.recommendations.order(:position).pluck(:position)).to eq([1, 2, 3, 4, 5])
  end

  it "rebuilds a section an earlier rebuild left parked, even when its statements did not change" do
    build
    evidence = section("4-2-1-1-diagnostico-clinico-y-paraclinico-en-el-adulto-joven-evidence")
    evidence.recommendations.where(position: [1, 2]).update_all("position = -position")

    expect(build.payload[:rebuilt]).to eq(1)
    expect(evidence.recommendations.order(:position).pluck(:position)).to eq([1, 2, 3, 4, 5, 6])
  end

  it "refuses to drop a recommendation a question cites, and changes nothing" do
    build
    cited = section("4-2-1-1-diagnostico-clinico-y-paraclinico-en-el-adulto-joven-good_practice").recommendations.sole
    create(:question, recommendation: cited)
    document.update!(body: table.sub(/^\/R.*?ginecoobstetricia\.\n/m, ""))

    result = build

    expect(result).to be_failure
    expect(result.errors.full_messages).to include(match(/IMSS-031-08: hay preguntas que citan/))
    expect(cited.reload).to be_persisted
  end

  it "keeps apart two headings that differ only in spelling" do
    statement = { text: "Se recomienda vigilancia.", label: "C", grade: "C", scale: nil, citation: nil,
                  kind: "recommendation", chapter: "4.1 Diagnóstico", heading: "4.1 Diagnóstico" }
    parser = Gpc::ArchiveRecommendationParser.new("")
    allow(Gpc::ArchiveRecommendationParser).to receive(:call).and_return(
      parser.success([statement, statement.merge(chapter: "4.1 DIAGNOSTICO", heading: "4.1 DIAGNOSTICO")])
    )

    build

    expect(derived.pluck(:external_id)).to eq(
      %w[20090101/4-1-diagnostico-recommendation 20090101/4-1-diagnostico-recommendation-2]
    )
    expect(derived.first).to have_attributes(chapter: "4.1 Diagnóstico", question_label: nil)
  end

  it "files a table with no numbered headings under one general section" do
    document.update!(body: file_fixture("gpc/archived_table_without_markers.txt").read)

    build

    expect(derived.pluck(:external_id)).to eq(%w[20090101/general-evidence])
    expect(derived.sole.menu_path).to eq("EVIDENCIAS")
  end

  it "builds nothing from a document with no evidence table" do
    document.update!(body: "Introducción sin tablas.")

    expect(build.payload).to eq(sections: 0, rebuilt: 0, recommendations: 0)
    expect(derived).to be_empty
  end
end

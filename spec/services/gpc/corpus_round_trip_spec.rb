require "rails_helper"

# Moving the corpus between environments is the only way the two hours of scraping
# survive a deploy, so the round trip is tested as one thing rather than as two halves
# that each pass alone.
RSpec.describe "corpus export and import" do
  let(:path) { Rails.root.join("tmp/spec-corpus-#{SecureRandom.hex(4)}.jsonl.gz").to_s }

  after { FileUtils.rm_f(path) }

  def export = Gpc::CorpusExporter.call(path)
  def import = Gpc::CorpusImporter.call(path)

  def build_corpus
    live = create(:guideline, catalog_key: "IMSS-028-22", title: "Atención en el embarazo")
    create(
      :guideline_section, guideline: live, external_id: "34142", position: 1,
      heading: "RECOMENDACIONES", clinical_question: "¿QUÉ BENEFICIOS APORTA?"
    )
    archived = create(:guideline, catalog_key: "IMSS-051-18", source: "web_archive")
    create(
      :guideline_section, guideline: archived, external_id: "20180101", position: 1,
      kind: "archived_document", heading: "RESUMEN", clinical_question: nil
    )
    [live, archived]
  end

  it "carries every guideline and section across" do
    build_corpus

    expect(export.payload).to include(guidelines: 2, sections: 2)

    Guideline.destroy_all
    result = import

    expect(result).to be_success
    expect(result.payload).to include(guidelines_created: 2, sections_created: 2)
    expect(Guideline.count).to eq(2)
    expect(GuidelineSection.count).to eq(2)
  end

  it "restores the fields a question will be cited from" do
    build_corpus
    export
    Guideline.destroy_all
    import

    section = Guideline.find_by(catalog_key: "IMSS-028-22").guideline_sections.sole

    expect(section).to have_attributes(
      external_id: "34142", heading: "RECOMENDACIONES", kind: "recommendation",
      clinical_question: "¿QUÉ BENEFICIOS APORTA?", position: 1
    )
    expect(section.body).to include("separador")
  end

  it "keeps a section attached to its own guideline, whatever the row ids are" do
    build_corpus
    export
    Guideline.destroy_all
    # Ids restart somewhere else entirely, which is exactly what happens on a fresh
    # production database.
    create(:guideline, catalog_key: "DECOY-001-20")
    import

    expect(Guideline.find_by(catalog_key: "IMSS-051-18").guideline_sections.sole.external_id)
      .to eq("20180101")
  end

  it "is idempotent, so re-importing over a scraped database changes nothing" do
    build_corpus
    export
    import

    expect(import.payload).to include(guidelines_updated: 2, sections_updated: 2)
    expect(Guideline.count).to eq(2)
    expect(GuidelineSection.count).to eq(2)
  end

  it "does not carry recommendations, which the far side rebuilds from the sections" do
    live, = build_corpus
    create(:recommendation, guideline_section: live.guideline_sections.first)
    export
    Recommendation.destroy_all
    Guideline.destroy_all
    import

    expect(Recommendation.count).to eq(0)
    expect(GuidelineSection.count).to eq(2)
  end

  describe "when the file is not what it should be" do
    it "fails on a missing file" do
      expect(Gpc::CorpusImporter.call("#{path}-nope").errors.full_messages.first).to include("No existe")
    end

    it "fails on a file that is not gzip" do
      File.write(path, "no soy gzip")

      expect(import.errors.full_messages.first).to include("no se pudo descomprimir")
    end

    it "fails on a line that is not JSON" do
      Zlib::GzipWriter.open(path) { |f| f.puts("{roto") }

      expect(import.errors.full_messages.first).to include("no es JSON")
    end

    it "fails on an unknown record type rather than skipping it" do
      Zlib::GzipWriter.open(path) { |f| f.puts({ record: "lo-que-sea" }.to_json) }

      expect(import.errors.full_messages.first).to include("Registro desconocido")
    end

    it "fails when a section names a guideline the file never defined" do
      Zlib::GzipWriter.open(path) do |f|
        f.puts({ record: "section", catalog_key: "AUSENTE-001-20", external_id: "1" }.to_json)
      end

      expect(import.errors.full_messages.first).to include("cita una guía ausente")
    end
  end
end

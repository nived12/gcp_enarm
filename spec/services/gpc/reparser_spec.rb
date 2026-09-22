require "rails_helper"

RSpec.describe Gpc::Reparser do
  let(:section) { create(:guideline_section) }
  let(:parsed) do
    { label: "A NICE Hong K, 2021", grade: "A", scale: "NICE", citation: "Hong K, 2021",
      text: "Se recomienda otorgar educación prenatal.", position: 1 }
  end

  it "rebuilds a live section whose statements the parser now reads differently" do
    create(:recommendation, guideline_section: section, text: "Texto de una versión anterior del parser.")

    result = described_class.call

    expect(section.recommendations.reload.sole.text).to eq("Se recomienda otorgar educación prenatal.")
    expect(result.payload).to include(sections: 1, before: 1, after: 1, conflicts: [])
  end

  it "leaves a section that parses the same alone, so its rows keep their ids" do
    kept = create(:recommendation, guideline_section: section, **parsed)

    described_class.call

    expect(section.recommendations.reload).to eq([kept])
  end

  it "reports a changed section a question cites instead of deleting the question's statement" do
    cited = create(:recommendation, guideline_section: section, text: "Texto de una versión anterior del parser.")
    create(:question, recommendation: cited)

    result = described_class.call

    expect(result.payload[:conflicts].sole).to include(section.guideline.catalog_key, "hay preguntas que citan")
    expect(section.recommendations.reload).to eq([cited])
  end

  it "clears statements from a section that is no longer graded" do
    create(:recommendation, guideline_section: create(:guideline_section, kind: "other"))

    expect(described_class.call.payload).to include(before: 1, after: 0)
  end

  describe "the archive" do
    let(:guideline) { create(:guideline, catalog_key: "IMSS-031-08", source: "web_archive") }
    let!(:document) do
      create(
        :guideline_section, guideline: guideline, kind: "archived_document", external_id: "20090101",
        body: file_fixture("gpc/archived_evidence_table.txt").read
      )
    end

    it "rebuilds every archived document's statements" do
      expect(described_class.call.payload).to include(archived_guidelines: 1, archived_recommendations: 15)
      expect(document.derived_sections.count).to eq(5)
    end

    it "reports a document the builder refused and carries on" do
      allow(Gpc::ArchiveSectionBuilder).to receive(:call)
        .and_return(Gpc::ArchiveSectionBuilder.new(document).failure("IMSS-031-08: conflicto"))

      result = described_class.call

      expect(result.payload).to include(conflicts: ["IMSS-031-08: conflicto"], archived_guidelines: 0)
    end

    it "does not count a document whose table yields nothing" do
      document.update!(body: "Sin tabla de evidencias.")

      expect(described_class.call.payload).to include(archived_guidelines: 0, archived_recommendations: 0)
    end
  end
end

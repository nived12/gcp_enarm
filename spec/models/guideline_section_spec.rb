require "rails_helper"

RSpec.describe GuidelineSection do
  describe "validations" do
    it "requires a heading" do
      section = build(:guideline_section, heading: nil)

      expect(section).not_to be_valid
      expect(section.errors).to be_of_kind(:heading, :blank)
    end

    it "requires a content hash" do
      expect(build(:guideline_section, content_hash: nil)).not_to be_valid
    end

    it "requires a position" do
      expect(build(:guideline_section, position: nil)).not_to be_valid
    end

    it "allows the same section id under a different guideline" do
      create(:guideline_section, external_id: "36777")

      expect(build(:guideline_section, external_id: "36777")).to be_valid
    end

    it "rejects the same section id twice under one guideline" do
      guideline = create(:guideline)
      create(:guideline_section, guideline: guideline, external_id: "36777")
      duplicate = build(:guideline_section, guideline: guideline, external_id: "36777")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors).to be_of_kind(:external_id, :taken)
    end
  end

  describe ".kind_from_heading" do
    it "reads the kind off the label the site uses" do
      expect(described_class.kind_from_heading("EVIDENCIAS")).to eq("evidence")
      expect(described_class.kind_from_heading("RECOMENDACIONES")).to eq("recommendation")
      expect(described_class.kind_from_heading("RECOMENDACIONES CLAVE")).to eq("key_recommendation")
      expect(described_class.kind_from_heading("PUNTOS DE BUENA PRÁCTICA")).to eq("good_practice")
    end

    it "matches the longer label first" do
      expect(described_class.kind_from_heading("Recomendaciones clave")).to eq("key_recommendation")
    end

    it "accepts the spelling without the accent, which some guidelines use" do
      expect(described_class.kind_from_heading("PUNTOS DE BUENA PRACTICA")).to eq("good_practice")
    end

    it "files everything else as other" do
      expect(described_class.kind_from_heading("CUADRO DE MEDICAMENTOS")).to eq("other")
      expect(described_class.kind_from_heading(nil)).to eq("other")
    end
  end

  describe "scopes" do
    it "counts the kinds that say what a clinician should do as actionable" do
      %w[evidence recommendation key_recommendation good_practice other].each do |kind|
        create(:guideline_section, kind: kind)
      end

      expect(described_class.actionable.pluck(:kind))
        .to match_array(%w[recommendation key_recommendation good_practice])
      expect(described_class.graded.count).to eq(4)
    end
  end

  describe "#graded?" do
    it "is true for the kinds whose separadores are grading strips" do
      expect(GuidelineSection::GRADED_KINDS.map { |kind| build(:guideline_section, kind: kind).graded? })
        .to all(be(true))
    end

    it "is false for everything else, where a separador means something else entirely" do
      expect(build(:guideline_section, kind: "other")).not_to be_graded
    end
  end

  it "takes its recommendations with it when it is destroyed" do
    section = create(:guideline_section)
    create(:recommendation, guideline_section: section)

    expect { section.destroy }.to change(Recommendation, :count).by(-1)
  end
end

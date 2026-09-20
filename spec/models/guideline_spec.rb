require "rails_helper"

RSpec.describe Guideline do
  describe "validations" do
    it "requires a catalog key, a title and a content hash" do
      guideline = described_class.new

      expect(guideline).not_to be_valid
      expect(guideline.errors.attribute_names).to include(:catalog_key, :title, :content_hash)
    end

    it "rejects a second row for the same catalog key" do
      create(:guideline, catalog_key: "IMSS-028-22")

      expect(build(:guideline, catalog_key: "IMSS-028-22")).not_to be_valid
    end
  end

  describe ".institution_from_catalog_key" do
    it "maps each published prefix to its institution" do
      expect(described_class.institution_from_catalog_key("IMSS-028-22")).to eq("imss")
      expect(described_class.institution_from_catalog_key("SS-160-22")).to eq("health_ministry")
      expect(described_class.institution_from_catalog_key("DIF-400-21")).to eq("dif")
    end

    it "is case-insensitive, because the archive is not consistent about it" do
      expect(described_class.institution_from_catalog_key("imss-028-22")).to eq("imss")
    end

    it "returns nil for a prefix no institution claims" do
      expect(described_class.institution_from_catalog_key("XYZ-001-99")).to be_nil
      expect(described_class.institution_from_catalog_key(nil)).to be_nil
    end
  end

  describe ".with_specialty_label" do
    it "finds guidelines tagged with the label, including multi-specialty ones" do
      obstetrics = create(:guideline, specialty_labels: ["Gineco-Obstetricia"])
      both = create(:guideline, specialty_labels: ["Pediatría", "Medicina Interna"])
      create(:guideline, specialty_labels: ["Medicina Interna"])

      expect(described_class.with_specialty_label("Gineco-Obstetricia")).to contain_exactly(obstetrics)
      expect(described_class.with_specialty_label("Pediatría")).to contain_exactly(both)
    end
  end

  describe "enums" do
    it "exposes prefixed predicates for institution and source" do
      guideline = create(:guideline, institution: "imss", source: "live_site")

      expect(guideline).to be_institution_imss
      expect(guideline).to be_source_live_site
    end
  end
end

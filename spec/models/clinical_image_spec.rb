require "rails_helper"

RSpec.describe ClinicalImage do
  describe ".kind_for" do
    it "reads the type off the label the guideline published" do
      expect(described_class.kind_for("CUADRO 2")).to eq("table")
      expect(described_class.kind_for("TABLA 1")).to eq("table")
      expect(described_class.kind_for("Diagrama de flujo 3")).to eq("algorithm")
      expect(described_class.kind_for("ESCALA DE GLASGOW")).to eq("scale")
      expect(described_class.kind_for("ANEXO CLÍNICO")).to eq("figure")
    end
  end

  describe ".reference_keys" do
    it "finds every figure a piece of text sends the reader to" do
      expect(described_class.reference_keys("Ver cuadro 1 y el Algoritmo 2"))
        .to eq(["cuadro 1", "algoritmo 2"])
    end

    it "matches across accents and case, which guidelines are not consistent about" do
      expect(described_class.reference_keys("consúltese el DIAGRAMA 4")).to eq(["diagrama 4"])
    end

    it "finds nothing in a recommendation that refers to no figure" do
      expect(described_class.reference_keys("Se recomienda vigilancia estrecha.")).to be_empty
    end
  end

  describe ".cited_by" do
    let(:guideline) { create(:guideline) }
    let(:section) { create(:guideline_section, guideline: guideline) }

    def recommendation(text)
      create(:recommendation, guideline_section: section, text: text)
    end

    it "pairs a recommendation with the figure it names" do
      image = create(:clinical_image, :stored, guideline_section: section, label: "CUADRO 1")
      cited = recommendation("Los aspectos esenciales son los siguientes (ver cuadro 1).")

      expect(described_class.cited_by([recommendation("Sin figura."), cited])).to eq([cited, image])
    end

    # A figure that never downloaded would render as a broken image in the middle of an
    # exam, which is worse than a case with no figure at all.
    it "ignores a figure whose file never arrived" do
      create(:clinical_image, guideline_section: section, label: "CUADRO 1")

      expect(described_class.cited_by([recommendation("ver cuadro 1")])).to be_nil
    end

    # Guidelines number their figures independently, so cuadro 1 of another guideline is
    # a different table about a different disease.
    it "never reaches into another guideline for a figure with the same number" do
      create(:clinical_image, :stored, label: "CUADRO 1")

      expect(described_class.cited_by([recommendation("ver cuadro 1")])).to be_nil
    end

    it "ignores a figure the recommendations do not mention" do
      create(:clinical_image, :stored, guideline_section: section, label: "CUADRO 9")

      expect(described_class.cited_by([recommendation("ver cuadro 1")])).to be_nil
    end

    it "has nothing to offer when the guideline published no figures" do
      expect(described_class.cited_by([recommendation("ver cuadro 1")])).to be_nil
    end

    it "has nothing to offer for an empty batch" do
      expect(described_class.cited_by([])).to be_nil
    end
  end

  describe "#reference_key" do
    it "is what a recommendation would write to point at this figure" do
      expect(build(:clinical_image, label: "CUADRO 2").reference_key).to eq("cuadro 2")
    end
  end
end

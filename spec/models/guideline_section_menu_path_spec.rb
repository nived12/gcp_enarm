require "rails_helper"

RSpec.describe GuidelineSection do
  describe "#menu_path" do
    it "reads as the clicks a reader has to make" do
      section = build(
        :guideline_section, chapter: "DIAGNÓSTICO", question_label: "PREGUNTA 3",
        heading: "RECOMENDACIONES CLAVE"
      )

      expect(section.menu_path).to eq("DIAGNÓSTICO › PREGUNTA 3 › RECOMENDACIONES CLAVE")
    end

    it "drops the question for a section that sits under none" do
      section = build(
        :guideline_section, chapter: "ANEXOS", question_label: nil,
        heading: "GLOSARIO DE TERMINOS"
      )

      expect(section.menu_path).to eq("ANEXOS › GLOSARIO DE TERMINOS")
    end

    it "falls back to the heading alone for an archived guideline, which has no menu" do
      section = build(
        :guideline_section, chapter: nil, question_label: nil,
        heading: "RESUMEN DE EVIDENCIAS Y RECOMENDACIONES"
      )

      expect(section.menu_path).to eq("RESUMEN DE EVIDENCIAS Y RECOMENDACIONES")
    end
  end
end

require "rails_helper"

RSpec.describe Questions::Prompt do
  let(:guideline) { create(:guideline, title: "Diagnóstico del síndrome coronario agudo") }
  let(:ecg) { build(:recommendation, text: "Se recomienda realizar\nelectrocardiograma de 12 derivaciones.") }
  let(:aspirin) { build(:recommendation, text: "Se recomienda iniciar aspirina 300 mg.") }

  def prompt(recommendations = [ecg, aspirin], **options)
    described_class.new(guideline, recommendations, **options).to_s
  end

  it "numbers the statements it is handed, in order, so the model can cite them by number" do
    expect(prompt).to include(
      "1. Se recomienda realizar electrocardiograma de 12 derivaciones.\n2. Se recomienda iniciar aspirina 300 mg."
    )
    expect(prompt).to include('"Diagnóstico del síndrome coronario agudo"')
  end

  # §9.1 of the convocatoria: the three cross-cutting contexts are where a case happens.
  it "sets the case where the exam sets it" do
    expect(prompt).to include("medicina\nfamiliar en el primer nivel, un servicio de urgencias")
    expect(prompt).to include("No sitúes el caso en una sala")
  end

  describe "how much of the patient the vignette carries" do
    it "asks for a whole-patient vignette and three questions on a full workup" do
      text = prompt(detail: :full_workup)

      expect(text).to include("paciente COMPLETO", "Signos vitales COMPLETOS", "3 preguntas")
    end

    it "asks for a short vignette and two questions when focused" do
      expect(prompt(detail: :focused)).to include("breve y centrada", "2 preguntas")
    end

    it "falls back to focused rather than trusting an unknown detail level" do
      expect(prompt(detail: :novela)).to include("breve y centrada")
    end
  end

  describe "language" do
    it "says nothing about language for a Spanish case" do
      expect(prompt).not_to include("EN INGLÉS")
    end

    it "asks for English, keeping the quote in Spanish so the citation gate still holds" do
      expect(prompt(locale: "en")).to include("EN INGLÉS", "cita textual se queda en español")
    end
  end

  describe "a figure" do
    let(:image) { build(:clinical_image, label: "CUADRO 1", caption: "CRITERIOS DE ESTRATIFICACIÓN") }

    it "names the figure and the statement that points at it, so the vignette is written towards it" do
      text = prompt(figure: [aspirin, image])

      expect(text).to include("recomendación 2, que remite a «CUADRO 1: CRITERIOS DE ESTRATIFICACIÓN»")
    end

    # The model never sees the image. Asking it about the contents would invent them, and
    # the citation gate only checks the quote — it could not catch a fabricated table row.
    it "tells the model not to describe what it cannot see" do
      expect(prompt(figure: [aspirin, image])).to include("No describas el contenido de la figura")
    end

    it "says nothing about figures when none was chosen" do
      expect(prompt).not_to include("figura")
    end
  end
end

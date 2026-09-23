require "rails_helper"

RSpec.describe Questions::SettingClassifier do
  def code(stem) = described_class.code_for(stem)

  describe ".code_for" do
    {
      "Acude a consulta de medicina familiar un paciente de 52 años." => "family_medicine",
      "Mujer de 24 años acude a su Unidad de Medicina Familiar para control prenatal." => "family_medicine",
      "Acude a consulta de primer nivel paciente femenina de 28 años." => "family_medicine",
      "Acude a centro de salud una paciente de 68 años para valoración integral." => "family_medicine",
      "A 52-year-old male presents to your primary care clinic for a routine check-up." => "family_medicine",
      "A 78-year-old male presents to the family medicine clinic for his assessment." => "family_medicine",
      "In a community health center, a 75-year-old woman seeks advice." => "family_medicine",
      "Masculino de 42 años es traído a urgencias por agitación psicomotriz." => "emergency",
      "Paciente de 32 años acude al servicio de urgencias gineco-obstétricas." => "emergency",
      "Se recibe en la sala de choque a un hombre de 30 años." => "emergency",
      "A 28-year-old female presents to the Emergency Department with fever." => "emergency",
      "En una jornada de salud pública comunitaria, acude una mujer de 45 años." => "public_health",
      "Durante una jornada de vigilancia epidemiológica en una escuela, se evalúa a un niño." => "public_health",
      "En el contexto de una campaña de vacunación, acude una adolescente de 13 años." => "public_health",
      "Durante un brote de sarampión en la comunidad se atiende a un lactante." => "public_health",
      "En un tamizaje comunitario se identifica a una mujer de 50 años." => "public_health",
      "Una brigada de salud visita una comunidad rural." => "public_health",
      "A 35-year-old male presents to the public health department during an outbreak." => "public_health",
      "A 45-year-old female presents to your community screening program." => "public_health"
    }.each do |stem, expected|
      it "reads #{expected} in “#{stem.truncate(60)}”" do
        expect(code(stem)).to eq(expected)
      end
    end

    it "reads a stem regardless of accents and capitals" do
      expect(code("EN UNA JORNADA DE SALUD PUBLICA se evalúa a un niño.")).to eq("public_health")
    end

    it "leaves a stem that names no place unknown" do
      expect(code("Recién nacido de 2 horas de vida con ictericia.")).to be_nil
      expect(code(nil)).to be_nil
    end

    it "leaves a hospital place that is none of the three unknown, and lets it outrank a later phrase" do
      expect(code("A 32-week newborn is admitted to the Neonatal Intensive Care Unit.")).to be_nil
      stem = "Masculino ingresado a la unidad de cuidados intensivos. Usted establece medidas de " \
             "vigilancia epidemiológica para prevenir neumonía."
      expect(code(stem)).to be_nil
    end

    it "takes the setting the story opens in when a later sentence names another" do
      stem = "Acude a su unidad de medicina familiar para control. Durante la espera pierde el estado " \
             "de alerta y se solicita traslado a urgencias."

      expect(code(stem)).to eq("family_medicine")
    end

    it "lets a public-health activity outrank the centro de salud it happens in" do
      stem = "Mujer de 35 años acude a un centro de salud como parte de un programa de vigilancia " \
             "epidemiológica comunitaria."

      expect(code(stem)).to eq("public_health")
    end

    it "reads where a referred patient is seen, not where they were sent from" do
      expect(code("Paciente enviado por su médico familiar al servicio de urgencias por disnea.")).to eq("emergency")
      expect(code("A 60-year-old referred by his family physician to the emergency department.")).to eq("emergency")
    end

    it "does not take a surgeon's urgency for the emergency service" do
      expect(code("Paciente de 45 años programado para laparotomía de urgencia.")).to be_nil
    end

    it "does not take a flare for an outbreak" do
      expect(code("Paciente con psoriasis que presenta durante un brote de psoriasis placas extensas.")).to be_nil
    end

    it "does not take a problem of public health for a public-health setting" do
      expect(code("La obesidad infantil es un problema de salud pública en México.")).to be_nil
    end
  end

  describe ".call" do
    let!(:emergency) { create(:emergency_setting) }
    let!(:family) { create(:family_medicine_setting) }
    let!(:public_health) { create(:public_health_setting) }

    let!(:in_emergency) { create(:clinical_case, stem: "Acude al servicio de urgencias por dolor torácico.") }
    let!(:in_consult) { create(:clinical_case, stem: "Acude a consulta de medicina familiar por tos.", locale: "en") }
    let!(:placeless) { create(:clinical_case, stem: "Recién nacido de 2 horas de vida con ictericia.") }
    let!(:already_set) do
      create(
        :clinical_case, stem: "Acude al servicio de urgencias por disnea.", setting: public_health,
        status: "retired"
      )
    end

    it "fills in the unknown settings and names what it could not read" do
      result = described_class.call.payload

      expect(result).to eq(classified: { "urgencias" => 1, "medicina-familiar" => 1 }, unclassified: [placeless.id])
      expect(in_emergency.reload.setting).to eq(emergency)
      expect(in_consult.reload.setting).to eq(family)
      expect(placeless.reload.setting).to be_nil
    end

    it "never overwrites a setting the model named or a reviewer corrected" do
      described_class.call

      expect(already_set.reload.setting).to eq(public_health)
    end

    it "counts without writing on a dry run" do
      result = described_class.call(dry_run: true).payload

      expect(result[:classified]).to eq("urgencias" => 1, "medicina-familiar" => 1)
      expect(ClinicalCase.where.not(setting_id: nil)).to contain_exactly(already_set)
    end

    it "reads only the cases it is handed" do
      described_class.call(cases: ClinicalCase.where(id: in_emergency.id))

      expect(in_consult.reload.setting).to be_nil
    end
  end
end

require "rails_helper"

RSpec.describe Gpc::TitleRepairer do
  subject(:repairer) { described_class.new(vocabulary) }

  let(:vocabulary) do
    %w[tratamiento de del la ataxia diagnóstico y fractura coordinador coordinadora ingreso a condicionar]
      .index_with { 10 }.tap { |counts| counts.default = 0 }
  end

  it "puts back the space before or after a short word, keeping the capitals" do
    expect(repairer.call("Diagnóstico y Tratamientode Fractura")).to eq("Diagnóstico y Tratamiento de Fractura")
    expect(repairer.call("Abordaje de laataxia")).to eq("Abordaje de la ataxia")
    expect(repairer.call("Diagnósticoy tratamiento")).to eq("Diagnóstico y tratamiento")
    expect(repairer.call("Ingresoa urgencias")).to eq("Ingreso a urgencias")
  end

  it "leaves words of the corpus, capitals and feminine endings whole" do
    expect(repairer.call("Coordinadora de ACONDICIONAR")).to eq("Coordinadora de ACONDICIONAR")
    unknown = vocabulary.except("coordinadora").tap { |counts| counts.default = 0 }
    expect(described_class.new(unknown).call("Coordinadora")).to eq("Coordinadora")
  end

  it "does not split off a part too short to be a word of its own" do
    expect(repairer.call("Lade")).to eq("Lade")
  end

  it "reads its vocabulary from the recommendations, not from the titles" do
    create(:recommendation, text: "Se recomienda tratamiento de la fractura.")

    expect(described_class.vocabulary).to include("tratamiento" => 1, "fractura" => 1)
  end
end

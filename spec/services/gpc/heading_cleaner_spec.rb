require "rails_helper"

RSpec.describe Gpc::HeadingCleaner do
  subject(:cleaner) { described_class.new(vocabulary) }

  # "ma", "te" and "n" are in the corpus as symbols, as they are in the real one.
  let(:vocabulary) do
    %w[vigilancia materna tratamiento no quirúrgico de escala evolución rotos ma te n na vigil]
      .index_with { 10 }.tap { |counts| counts.default = 0 }
  end

  it "keeps a heading made of the corpus's words" do
    expect(cleaner.call("4.4 Vigilancia materna")).to eq("4.4 Vigilancia materna")
    expect(cleaner.call("4.2.1 Tratamiento no quirúrgico")).to eq("4.2.1 Tratamiento no quirúrgico")
  end

  it "withholds a heading whose letters extraction lost" do
    expect(cleaner.call("4.4 Vigil n i a ma te na")).to be_nil
    expect(cleaner.call("4.2.1 Tratami ento no quirúrgi co")).to be_nil
    expect(cleaner.call("4.2.5 Ot ras terapi as")).to be_nil
  end

  it "does not judge words set in capitals, nor a single unknown word" do
    expect(cleaner.call("ESCALA AAO-HNSF Y JKMS")).to eq("ESCALA AAO-HNSF Y JKMS")
    expect(cleaner.call("Escala de Glasgow")).to eq("Escala de Glasgow")
    expect(cleaner.call("Evolución de AC no rotos")).to be_present
  end

  it "passes an absent heading through" do
    expect(cleaner.call(nil)).to be_nil
  end
end

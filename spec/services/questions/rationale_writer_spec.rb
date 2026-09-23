require "rails_helper"

RSpec.describe Questions::RationaleWriter do
  let(:guideline) { create(:guideline) }
  let(:section) { create(:guideline_section, guideline: guideline, kind: "recommendation") }
  let(:cited) { create(:recommendation, guideline_section: section, text: "Se sugiere capnografía durante la RCP.") }
  let(:clinical_case) do
    create(:clinical_case, guideline: guideline, stem: "Mujer de 54 años en fibrilación ventricular.")
  end
  let!(:question) do
    create(
      :question, clinical_case: clinical_case, position: 1, recommendation: cited, explanation: "Mide EtCO2.",
      text: "¿Qué monitoriza la calidad de las compresiones?"
    ).tap do |question|
      %w[Capnógrafo Pulsioxímetro Presión\ invasiva ECG\ continuo].each.with_index(1) do |text, position|
        create(:answer_option, question: question, position: position, text: text, correct: position == 1)
      end
    end
  end

  def stub_model(payload)
    allow(Llm::Completion).to receive(:call).and_return(
      ApplicationService::Response.new(
        success: true, errors: nil,
        payload: { content: payload.is_a?(String) ? payload : payload.to_json,
                   input_tokens: 900, output_tokens: 300, reasoning_tokens: 0, cost_usd: 0.0007 }
      )
    )
  end

  it "shows the model the rest of the guideline, where a distractor may apply after all" do
    create(
      :recommendation, guideline_section: section,
      text: "Tras la RCE, monitorización electrocardiográfica continua."
    )
    stub_model("questions" => [])

    described_class.call(clinical_case)

    expect(Llm::Completion).to have_received(:call).with(
      hash_including(
        role: :generator, prompt: a_string_including("Tras la RCE", "A) Capnógrafo (correcta)", "Mide EtCO2.")
      )
    )
  end

  it "stores a reason on each distractor and never on the correct option" do
    rationales = {
      "A" => "No debería escribirse.", "B" => " La oximetría  mide oxigenación. ",
      "D" => "El ECG se indica tras la RCE.", "E" => "No existe.", "C" => " "
    }
    stub_model("questions" => [{ "question" => 1, "rationales" => rationales }])

    result = described_class.call(clinical_case)

    expect(result.payload).to eq(written: 2)
    expect(question.answer_options.reload.map(&:rationale))
      .to eq([nil, "La oximetría mide oxigenación.", nil, "El ECG se indica tras la RCE."])
  end

  it "writes in English for an English case" do
    clinical_case.update!(locale: "en")
    stub_model("questions" => [])

    described_class.call(clinical_case)

    expect(Llm::Completion).to have_received(:call).with(hash_including(prompt: a_string_including("EN INGLÉS")))
  end

  it "ignores a question number or a shape it does not know" do
    stub_model(
      "questions" => [{ "question" => 7, "rationales" => { "B" => "x" } },
      { "question" => 1, "rationales" => "B" }]
    )

    expect(described_class.call(clinical_case).payload).to eq(written: 0)
  end

  it "charges its tokens to the run" do
    run = create(:generation_run, purpose: "rationales")
    stub_model("questions" => [])

    described_class.call(clinical_case, run: run)

    expect(run.reload).to have_attributes(input_tokens: 900, output_tokens: 300, attempts: 1, calls: 1)
  end

  it "leaves a new rationale unjudged, whatever the old one's verdict was" do
    question.answer_options.second.update!(rationale: "Vieja.", rationale_verdict: "sound")
    stub_model("questions" => [{ "question" => 1, "rationales" => { "B" => "Nueva." } }])

    described_class.call(clinical_case)

    expect(question.answer_options.second.reload).to have_attributes(rationale: "Nueva.", rationale_verdict: nil)
  end

  describe "rewriting what the verifier rejected" do
    before do
      question.answer_options.second.update!(
        rationale: "Es inaceptable.", rationale_verdict: "overstated", rationale_note: "Exagera."
      )
      question.answer_options.third.update!(rationale: "Mide presión.", rationale_verdict: "sound")
    end

    it "shows the rejected text and the reviewer's reason, and rewrites only that one" do
      stub_model("questions" => [{ "question" => 1, "rationales" => { "B" => "Mide oxigenación.", "C" => "Otra." } }])

      result = described_class.call(clinical_case, rewrite: true)

      expect(Llm::Completion).to have_received(:call)
        .with(hash_including(prompt: a_string_including("RECHAZADA: Es inaceptable.", "Motivo del revisor: Exagera.")))
      expect(result.payload).to eq(written: 1)
      expect(question.answer_options.reload.map(&:rationale).drop(1).first(2)).to eq(
        ["Mide oxigenación.",
        "Mide presión."]
      )
      expect(question.answer_options.second).to have_attributes(rationale_verdict: nil, rationale_note: nil)
    end

    it "has nothing to do when nothing was rejected" do
      question.answer_options.second.update!(rationale_verdict: "sound")

      expect(described_class.call(clinical_case, rewrite: true)).to be_failure
    end
  end

  it "fails on a reply it cannot read, or when the provider fails" do
    stub_model("no es json")
    expect(described_class.call(clinical_case)).to be_failure

    allow(Llm::Completion).to receive(:call).and_return(
      ApplicationService::Response.new(
        success: false, payload: nil, errors: ActiveModel::Errors.new(nil).tap { |e|
          e.add(:base, "caído")
        }
      )
    )
    expect(described_class.call(clinical_case).errors.full_messages).to eq(["caído"])
  end

  it "has nothing to do for a case without a cited statement" do
    question.update!(recommendation: nil)

    expect(described_class.call(clinical_case)).to be_failure
  end
end

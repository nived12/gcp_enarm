require "rails_helper"

RSpec.describe Questions::RationaleVerifier do
  let(:clinical_case) { create(:published_case, questions_count: 1, stem: "Hombre de 54 años con dolor torácico.") }
  let(:options) { clinical_case.questions.first.answer_options }

  def stub_verifier(payload)
    allow(Llm::Completion).to receive(:call).and_return(
      ApplicationService::Response.new(
        success: true, errors: nil,
        payload: { content: payload.is_a?(String) ? payload : payload.to_json,
                   input_tokens: 1_500, output_tokens: 200, reasoning_tokens: 0, cost_usd: 0.00069 }
      )
    )
  end

  def judgement(option, verdict, note = "")
    { "question" => 1, "option" => option, "verdict" => verdict, "note" => note }
  end

  def prompt_sent
    prompt = nil
    expect(Llm::Completion).to have_received(:call) { |**arguments| prompt = arguments[:prompt] }
    prompt
  end

  it "stores each verdict on its option, with the reason only when it rejects the rationale" do
    stub_verifier(
      "rationales" => [
            judgement("A", "overstated", "Dice inaceptable."), judgement("C", "sound", "Correcto."),
            judgement("D", "Contradicted ", "La guía no lo dice.")
          ]
    )

    result = described_class.call(clinical_case)

    expect(result.payload).to eq(sound: 1, overstated: 1, contradicted: 1)
    expect(options.reload.map { |option| [option.rationale_verdict, option.rationale_note] }).to eq(
      [["overstated", "Dice inaceptable."], [nil, nil], ["sound", nil], ["contradicted", "La guía no lo dice."]]
    )
  end

  # It must see the answer to judge why the others are not it, which is exactly why this
  # is a call apart from the blind one in Questions::Verifier.
  it "shows the marked answer, each rationale and the rest of the guideline, as the verifier role" do
    create(
      :recommendation, guideline_section: clinical_case.questions.first.recommendation.guideline_section,
      text: "Tras la RCE, monitorización electrocardiográfica continua."
    )
    stub_verifier("rationales" => [])

    described_class.call(clinical_case)

    expect(Llm::Completion).to have_received(:call).with(hash_including(role: :verifier))
    expect(prompt_sent).to include(
      "B) Electrocardiograma de 12 derivaciones (correcta)", "Razón: Troponina I no es el estudio inicial",
      "Tras la RCE", "overstated"
    )
  end

  it "sends only the rationales nobody has judged yet" do
    options.find_by!(text: "Troponina I").update!(rationale_verdict: "sound")
    stub_verifier("rationales" => [judgement("A", "contradicted")])

    described_class.call(clinical_case)

    expect(prompt_sent).not_to include("Razón: Troponina I")
    expect(options.reload.first.rationale_verdict).to eq("sound")
  end

  it "drops a verdict it does not know, a letter it did not send and a question that does not exist" do
    stub_verifier(
      "rationales" => [
            judgement("A", "dudoso"), judgement("B", "sound"), judgement("Z", "sound"),
            judgement("A", "sound").merge("question" => 4), judgement("A", "sound").merge("question" => 0)
          ]
    )

    expect(described_class.call(clinical_case).payload).to eq(sound: 0, overstated: 0, contradicted: 0)
    expect(options.reload.map(&:rationale_verdict).compact).to be_empty
  end

  it "refuses a case with no rationale left to judge" do
    clinical_case.questions.each { |question| question.answer_options.update_all(rationale_verdict: "sound") }

    expect(described_class.call(clinical_case).errors.full_messages.to_sentence).to include("no tiene razones")
  end

  it "passes the provider's failure through" do
    allow(Llm::Completion).to receive(:call).and_return(
      ApplicationService::Response.new(success: false, payload: nil, errors: ActiveModel::Errors.new(Object.new))
    )

    expect(described_class.call(clinical_case)).to be_failure
  end

  it "charges an unreadable reply to the run and fails" do
    run = create(:generation_run, purpose: "verification")
    stub_verifier("```json\nno es json\n```")

    expect(described_class.call(clinical_case, run: run).errors.full_messages.to_sentence).to include("JSON legible")
    expect(run.reload).to have_attributes(input_tokens: 1_500, output_tokens: 200, calls: 1, attempts: 1)
  end
end

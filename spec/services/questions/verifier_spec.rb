require "rails_helper"

RSpec.describe Questions::Verifier do
  let(:clinical_case) { create(:clinical_case, stem: "Paciente de 54 años con dolor torácico.") }
  let(:recommendation) do
    create(:recommendation, text: "Se recomienda realizar electrocardiograma de 12 derivaciones.")
  end

  def build_question(position: 1, correct_at: 1)
    question = create(
      :question, clinical_case: clinical_case, position: position,
      recommendation: recommendation, source_quote: "electrocardiograma de 12 derivaciones"
    )
    2.times do |index|
      create(
        :answer_option, question: question, position: index + 1,
        text: "Opción #{index + 1}", correct: index + 1 == correct_at
      )
    end
    question
  end

  def stub_verifier(payload)
    allow(Llm::Completion).to receive(:call).and_return(
      ApplicationService::Response.new(
        success: true, errors: nil,
        payload: { content: payload.is_a?(String) ? payload : payload.to_json,
                   input_tokens: 400, output_tokens: 120, reasoning_tokens: 0, cost_usd: 0.000264 }
      )
    )
  end

  def judgement(question: 1, option: "A", decidable: true, note: "Lo dice la recomendación.")
    { "question" => question, "option" => option, "decidable" => decidable, "note" => note }
  end

  it "supports a case when the second opinion picks the same option" do
    build_question
    stub_verifier("questions" => [judgement])

    result = described_class.call(clinical_case)

    expect(result.payload[:verdict]).to eq("supported")
    expect(clinical_case.reload).to have_attributes(verification_verdict: "supported")
    expect(clinical_case.verified_at).to be_present
  end

  # The point of the whole pass. A model shown which answer is marked correct agrees with
  # it; one asked to choose has to disagree out loud.
  it "marks a case unsupported when the other family chooses a different option" do
    build_question(correct_at: 1)
    stub_verifier("questions" => [judgement(option: "B", note: "La recomendación indica lo contrario.")])

    expect(described_class.call(clinical_case).payload[:verdict]).to eq("unsupported")
    expect(clinical_case.reload.verification_notes).to include("La recomendación indica lo contrario")
  end

  it "marks a case ambiguous when the recommendation does not settle the question" do
    build_question
    stub_verifier("questions" => [judgement(decidable: false, note: "No alcanza para decidir.")])

    expect(described_class.call(clinical_case).payload[:verdict]).to eq("ambiguous")
  end

  # Silence is not assent: a case cannot pass on the questions the verifier happened to
  # answer, because ClinicalCase#publishable? reads this column and nothing else.
  it "refuses to support a case whose questions were not all judged" do
    build_question(position: 1)
    build_question(position: 2)
    stub_verifier("questions" => [judgement])

    expect(described_class.call(clinical_case).payload[:verdict]).to eq("ambiguous")
    expect(clinical_case.reload).not_to be_publishable
  end

  it "takes a live case off the bank the moment it loses its support" do
    clinical_case.update!(verification_verdict: "supported", status: "published")
    build_question
    stub_verifier("questions" => [judgement(option: "B")])

    described_class.call(clinical_case)

    expect(clinical_case.reload).to have_attributes(verification_verdict: "unsupported", status: "draft")
  end

  it "leaves a case's status alone otherwise — publishing is the publisher's decision" do
    build_question
    stub_verifier("questions" => [judgement])

    described_class.call(clinical_case)

    expect(clinical_case.reload).to have_attributes(verification_verdict: "supported", status: "draft")
  end

  it "takes the worst verdict across a case, because exams select whole cases" do
    build_question(position: 1)
    build_question(position: 2, correct_at: 1)
    stub_verifier("questions" => [judgement, judgement(question: 2, option: "B")])

    expect(described_class.call(clinical_case).payload[:verdict]).to eq("unsupported")
  end

  # Numbered options were answered zero-based: on the pilot the verifier agreed in its
  # own note and was recorded as disputing the answer.
  it "reads an answer it cannot place as ambiguous, not as a dispute" do
    build_question(correct_at: 1)

    [0, "E"].each do |unreadable|
      stub_verifier("questions" => [judgement(option: unreadable)])

      expect(described_class.call(clinical_case).payload[:verdict]).to eq("ambiguous")
    end
    expect(clinical_case.reload.verification_notes).to be_present
  end

  it "accepts a lower-case letter" do
    build_question(correct_at: 2)
    stub_verifier("questions" => [judgement(option: " b ")])

    expect(described_class.call(clinical_case).payload[:verdict]).to eq("supported")
  end

  # Told the statement cannot settle it, the model still has to fill in an option, and
  # a guess that misses is not a finding against the answer.
  it "records a question the statement cannot settle as ambiguous, whatever option it guessed" do
    build_question(correct_at: 1)
    stub_verifier("questions" => [judgement(option: "C", decidable: false, note: "No alcanza para decidir.")])

    expect(described_class.call(clinical_case).payload[:verdict]).to eq("ambiguous")
  end

  it "ignores a judgement about a question that does not exist" do
    build_question
    stub_verifier("questions" => [judgement, judgement(question: 9)])

    expect(described_class.call(clinical_case).payload[:verdict]).to eq("supported")
  end

  it "is ambiguous when the verifier judged nothing at all" do
    build_question
    stub_verifier("questions" => [])

    expect(described_class.call(clinical_case).payload[:verdict]).to eq("ambiguous")
  end

  it "refuses a case with no question that carries both a citation and an answer" do
    create(:question, clinical_case: clinical_case, recommendation: nil)

    expect(described_class.call(clinical_case).errors.full_messages.to_sentence)
      .to include("no tiene preguntas verificables")
  end

  it "passes the provider's failure through rather than inventing a verdict" do
    build_question
    allow(Llm::Completion).to receive(:call).and_return(
      ApplicationService::Response.new(success: false, payload: nil, errors: ActiveModel::Errors.new(Object.new))
    )

    expect(described_class.call(clinical_case)).to be_failure
    expect(clinical_case.reload.verification_verdict).to be_nil
  end

  it "fails on a reply that is not JSON" do
    build_question
    stub_verifier("no soy json")

    expect(described_class.call(clinical_case).errors.full_messages.to_sentence)
      .to include("no devolvió JSON legible")
  end

  it "strips the markdown fence some providers wrap their JSON in" do
    build_question
    stub_verifier("```json\n#{{ "questions" => [judgement] }.to_json}\n```")

    expect(described_class.call(clinical_case).payload[:verdict]).to eq("supported")
  end

  it "bills the verification to its own run, separate from generation" do
    build_question
    run = create(:generation_run, purpose: "verification", provider: "deepseek", model: "deepseek-flash")
    stub_verifier("questions" => [judgement])

    described_class.call(clinical_case, run: run)

    expect(run.reload).to have_attributes(
      input_tokens: 400, output_tokens: 120, cost_usd: 0.000264, attempts: 1, calls: 1
    )
  end

  describe "the distractor rationales" do
    def with_rationale
      question = build_question(correct_at: 1)
      question.answer_options.find_by!(correct: false).update!(rationale: "No es la primera prueba.")
    end

    it "has a supported case's rationales judged next, on the same run" do
      with_rationale
      run = create(:generation_run, purpose: "verification")
      stub_verifier("questions" => [judgement])
      allow(Questions::RationaleVerifier).to receive(:call).and_return(
        ApplicationService::Response.new(success: true, errors: nil, payload: { sound: 1 })
      )

      result = described_class.call(clinical_case, run: run)

      expect(result.payload[:rationales]).to eq(sound: 1)
      expect(Questions::RationaleVerifier).to have_received(:call).with(clinical_case, run: run)
    end

    it "keeps the verdict when judging the rationales fails, and says why" do
      with_rationale
      stub_verifier("questions" => [judgement])
      errors = ActiveModel::Errors.new(ClinicalCase.new).tap { |e| e.add(:base, "sin respuesta") }
      allow(Questions::RationaleVerifier).to receive(:call)
        .and_return(ApplicationService::Response.new(success: false, errors: errors, payload: nil))

      result = described_class.call(clinical_case)

      expect(result.payload).to include(verdict: "supported", rationales: { error: "sin respuesta" })
    end

    it "does not pay to judge the rationales of a case that cannot go live, or of one without any" do
      with_rationale
      allow(Questions::RationaleVerifier).to receive(:call)
      stub_verifier("questions" => [judgement(option: "B")])
      expect(described_class.call(clinical_case).payload[:rationales]).to be_nil

      AnswerOption.update_all(rationale: nil)
      stub_verifier("questions" => [judgement])
      expect(described_class.call(clinical_case).payload[:rationales]).to be_nil
      expect(Questions::RationaleVerifier).not_to have_received(:call)
    end
  end

  describe "the prompt" do
    def prompt_sent
      captured = nil
      allow(Llm::Completion).to receive(:call) do |**arguments|
        captured = arguments[:prompt]
        ApplicationService::Response.new(
          success: true, errors: nil,
          payload: { content: { "questions" => [judgement] }.to_json, input_tokens: 1,
                     output_tokens: 1, reasoning_tokens: 0 }
        )
      end
      described_class.call(clinical_case)
      captured
    end

    # If it knew which one was marked correct it would agree with it, which is exactly
    # the check this pass is meant to be.
    it "never reveals which option the generator marked correct" do
      build_question(correct_at: 2)

      expect(prompt_sent).to include("A) Opción 1", "B) Opción 2")
      expect(prompt_sent).not_to match(/correcta|correct/i)
    end

    it "gives the recommendation and tells the model to use nothing else" do
      build_question

      expect(prompt_sent).to include("electrocardiograma de 12 derivaciones")
      expect(prompt_sent).to include("ÚNICAMENTE la recomendación")
    end
  end
end

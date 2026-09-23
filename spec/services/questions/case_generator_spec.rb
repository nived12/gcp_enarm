require "rails_helper"

RSpec.describe Questions::CaseGenerator do
  let(:guideline) { create(:guideline, year: Date.current.year) }
  let(:section) { create(:guideline_section, guideline: guideline, kind: "recommendation") }
  let!(:recommendation) do
    create(
      :recommendation, guideline_section: section, grade: "A",
      text: "Se recomienda realizar electrocardiograma de 12 derivaciones."
    )
  end

  def stub_model(payload)
    allow(Llm::Completion).to receive(:call).and_return(
      ApplicationService::Response.new(
        success: true, errors: nil,
        payload: { content: payload.is_a?(String) ? payload : payload.to_json,
                   input_tokens: 600, output_tokens: 1_200, reasoning_tokens: 0, cost_usd: 0.00195 }
      )
    )
  end

  def options(correct_count: 1, total: 4)
    Array.new(total) { |i| { "text" => "Opción #{i}", "correct" => i < correct_count } }
  end

  def question(quote: "electrocardiograma de 12 derivaciones", index: 1, **overrides)
    { "text" => "¿Cuál es el estudio inicial?", "explanation" => "Porque sí",
      "recommendation" => index, "quote" => quote, "options" => options }.merge(overrides)
  end

  def one_case(*questions)
    { "cases" => [{ "stem" => "Paciente de 54 años con dolor torácico.", "questions" => questions }] }
  end

  it "refuses a guideline with no actionable recommendations" do
    empty = create(:guideline)

    result = described_class.call(empty)

    expect(result).to be_failure
    expect(result.errors.full_messages.to_sentence).to include("no tiene recomendaciones")
  end

  it "passes the provider's failure through rather than inventing a case" do
    allow(Llm::Completion).to receive(:call).and_return(
      ApplicationService::Response.new(
        success: false, payload: nil,
        errors: ActiveModel::Errors.new(Object.new)
      )
    )

    expect(described_class.call(guideline)).to be_failure
  end

  it "fails when the model does not return JSON" do
    stub_model("lo siento, no puedo")

    result = described_class.call(guideline)

    expect(result).to be_failure
    expect(result.errors.full_messages.to_sentence).to include("JSON legible")
  end

  it "builds a case with its questions and options" do
    stub_model(one_case(question))

    result = described_class.call(guideline)
    kase = result.payload[:cases].first

    expect(result).to be_success
    expect(kase.stem).to include("dolor torácico")
    expect(kase.questions.size).to eq(1)
    expect(kase.questions.first.answer_options.size).to eq(4)
    expect(kase.questions.first.recommendation).to eq(recommendation)
  end

  describe "the generation run" do
    it "records tokens, cases and rejections" do
      run = create(:generation_run)
      stub_model(one_case(question, question(quote: "inventado")))

      described_class.call(guideline, run: run)

      expect(run.reload).to have_attributes(
        input_tokens: 600, output_tokens: 1_200, cost_usd: 0.00195,
        cases_created: 1, rejections: 1, attempts: 2
      )
    end

    it "works without a run at all" do
      stub_model(one_case(question))

      expect(described_class.call(guideline)).to be_success
    end
  end

  it "writes from the window of statements it is handed" do
    later = create(:recommendation, guideline_section: section, text: "Se recomienda iniciar aspirina 300 mg.")
    stub_model(one_case(question(quote: "iniciar aspirina 300 mg")))

    result = described_class.call(guideline, recommendations: [later])

    expect(Llm::Completion).to have_received(:call) do |prompt:, **|
      expect(prompt).to include("1. Se recomienda iniciar aspirina 300 mg.")
      expect(prompt).not_to include("electrocardiograma")
    end
    expect(result.payload[:cases].sole.questions.sole.recommendation).to eq(later)
  end

  # The detail level and the language are the prompt's and the builder's business; this
  # only proves the generator hands them on.
  it "passes the rotation's choices through to the prompt and the saved case" do
    stub_model(one_case(question))

    kase = described_class.call(guideline, detail: :full_workup, locale: "en").payload[:cases].sole

    expect(kase.locale).to eq("en")
    expect(Llm::Completion).to have_received(:call) do |prompt:, **|
      expect(prompt).to include("paciente COMPLETO", "EN INGLÉS")
    end
  end

  it "reads JSON the model wrapped in a markdown fence" do
    stub_model("```json\n#{one_case(question).to_json}\n```")

    expect(described_class.call(guideline).payload[:cases].size).to eq(1)
  end
end

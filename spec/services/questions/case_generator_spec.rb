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
                   input_tokens: 600, output_tokens: 1_200, reasoning_tokens: 0 }
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

  describe "what it refuses to keep" do
    it "drops a question whose quote is not in the recommendation" do
      stub_model(one_case(question(quote: "angiografía coronaria inmediata")))

      result = described_class.call(guideline)

      expect(result.payload[:cases]).to be_empty
      expect(result.payload[:rejected]).to eq(1)
    end

    it "drops a question that does not offer exactly four options" do
      stub_model(one_case(question(options: options(total: 3))))

      expect(described_class.call(guideline).payload[:cases]).to be_empty
    end

    it "drops a question with more than one correct answer" do
      stub_model(one_case(question(options: options(correct_count: 2))))

      expect(described_class.call(guideline).payload[:cases]).to be_empty
    end

    it "drops a question citing a recommendation number that was never sent" do
      stub_model(one_case(question(index: 99)))

      expect(described_class.call(guideline).payload[:cases]).to be_empty
    end

    it "keeps the good questions in a case that also had a bad one" do
      stub_model(one_case(question, question(quote: "inventado")))

      result = described_class.call(guideline)

      expect(result.payload[:cases].first.questions.size).to eq(1)
      expect(result.payload[:rejected]).to eq(1)
    end

    it "skips a case with no vignette" do
      stub_model({ "cases" => [{ "stem" => "", "questions" => [question] }] })

      expect(described_class.call(guideline).payload[:cases]).to be_empty
    end

    it "skips a case with no questions" do
      stub_model({ "cases" => [{ "stem" => "Paciente.", "questions" => [] }] })

      expect(described_class.call(guideline).payload[:cases]).to be_empty
    end
  end

  describe "difficulty" do
    it "calls a case from strong evidence an easier item" do
      stub_model(one_case(question))

      expect(described_class.call(guideline).payload[:cases].first).to be_difficulty_low
    end

    it "calls a case from weak evidence a harder one" do
      recommendation.update!(grade: "D")
      stub_model(one_case(question))

      expect(described_class.call(guideline).payload[:cases].first).to be_difficulty_high
    end

    it "sits in the middle for a grade it does not recognise" do
      recommendation.update!(grade: "2b")
      stub_model(one_case(question))

      expect(described_class.call(guideline).payload[:cases].first).to be_difficulty_medium
    end

    it "sits in the middle when the recommendation carries no grade" do
      recommendation.update!(grade: nil)
      stub_model(one_case(question))

      expect(described_class.call(guideline).payload[:cases].first).to be_difficulty_medium
    end
  end

  describe "the generation run" do
    it "records tokens, cases and rejections" do
      run = create(:generation_run)
      stub_model(one_case(question, question(quote: "inventado")))

      described_class.call(guideline, run: run)

      expect(run.reload).to have_attributes(
        input_tokens: 600, output_tokens: 1_200,
        cases_created: 1, rejections: 1, attempts: 2
      )
    end

    it "works without a run at all" do
      stub_model(one_case(question))

      expect(described_class.call(guideline)).to be_success
    end
  end

  describe "how much of the patient the vignette carries" do
    it "asks for a whole-patient vignette and three questions on a full workup" do
      stub_model(one_case(question, question(index: 1), question(index: 1)))

      described_class.call(guideline, detail: :full_workup)

      expect(Llm::Completion).to have_received(:call) do |prompt:, **|
        expect(prompt).to include("paciente COMPLETO")
        expect(prompt).to include("Signos vitales COMPLETOS")
        expect(prompt).to include("3 preguntas")
      end
    end

    it "asks for a short vignette and two questions when focused" do
      stub_model(one_case(question))

      described_class.call(guideline, detail: :focused)

      expect(Llm::Completion).to have_received(:call) do |prompt:, **|
        expect(prompt).to include("breve y centrada")
        expect(prompt).to include("2 preguntas")
      end
    end

    it "falls back to focused rather than trusting an unknown detail level" do
      stub_model(one_case(question))

      described_class.call(guideline, detail: :novela)

      expect(Llm::Completion).to have_received(:call) do |prompt:, **|
        expect(prompt).to include("breve y centrada")
      end
    end
  end

  describe "language" do
    it "leaves the case in Spanish by default" do
      stub_model(one_case(question))

      kase = described_class.call(guideline).payload[:cases].first

      expect(kase.locale).to eq("es")
      expect(Llm::Completion).to have_received(:call) do |prompt:, **|
        expect(prompt).not_to include("EN INGLÉS")
      end
    end

    it "asks for English and records it, keeping the quote in Spanish so the gate still holds" do
      stub_model(one_case(question))

      kase = described_class.call(guideline, locale: "en").payload[:cases].first

      expect(kase.locale).to eq("en")
      expect(Llm::Completion).to have_received(:call) do |prompt:, **|
        expect(prompt).to include("EN INGLÉS")
        expect(prompt).to include("cita textual se queda en español")
      end
    end
  end

  it "labels the case with the guideline's topic and specialty when it has one" do
    topic = create(:topic)
    create(:guideline_topic, guideline: guideline, topic: topic)
    stub_model(one_case(question))

    kase = described_class.call(guideline).payload[:cases].first

    expect(kase.topic).to eq(topic)
    expect(kase.specialty).to eq(topic.branch.specialty)
  end
end

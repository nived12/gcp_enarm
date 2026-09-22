require "rails_helper"

RSpec.describe Questions::CaseBuilder do
  let(:guideline) { create(:guideline) }
  let(:section) { create(:guideline_section, guideline: guideline, kind: "recommendation") }
  let(:recommendation) do
    create(
      :recommendation, guideline_section: section, grade: "A",
      text: "Se recomienda realizar electrocardiograma de 12 derivaciones."
    )
  end

  def options(correct_count: 1, total: 4)
    Array.new(total) { |i| { "text" => "Opción #{i}", "correct" => i < correct_count } }
  end

  def question(quote: "electrocardiograma de 12 derivaciones", number: 1, **overrides)
    { "text" => "¿Cuál es el estudio inicial?", "explanation" => "Porque sí",
      "recommendation" => number, "quote" => quote, "options" => options }.merge(overrides.stringify_keys)
  end

  def one_case(*questions)
    { "cases" => [{ "stem" => "Paciente de 54 años con dolor torácico.", "questions" => questions }] }
  end

  def build_from(payload, recommendations: [recommendation], **options)
    described_class.call(payload, guideline: guideline, recommendations: recommendations, **options).payload
  end

  it "saves a case with its questions and options" do
    kase = build_from(one_case(question))[:cases].sole

    expect(kase).to be_persisted
    expect(kase).to have_attributes(
      stem: "Paciente de 54 años con dolor torácico.", locale: "es",
      source: "gpc_generated", guideline: guideline
    )
    expect(kase.questions.sole.answer_options.size).to eq(4)
    expect(kase.questions.sole.recommendation).to eq(recommendation)
  end

  it "records the language it was asked for" do
    expect(build_from(one_case(question), locale: "en")[:cases].sole.locale).to eq("en")
  end

  it "files the case under the guideline's main topic and its specialty" do
    topic = create(:guideline_topic, guideline: guideline).topic

    kase = build_from(one_case(question))[:cases].sole

    expect(kase).to have_attributes(topic: topic, specialty: topic.branch.specialty)
  end

  describe "what it refuses to keep" do
    it "drops a question whose quote is not in the recommendation" do
      built = build_from(one_case(question(quote: "angiografía coronaria inmediata")))

      expect(built).to eq(cases: [], rejected: 1)
    end

    it "drops a question that does not offer exactly four options" do
      expect(build_from(one_case(question(options: options(total: 3))))[:cases]).to be_empty
    end

    it "drops a question with more than one correct answer" do
      expect(build_from(one_case(question(options: options(correct_count: 2))))[:cases]).to be_empty
    end

    # The model numbers the statements itself. Number 0 once read as "the last one".
    it "drops a question citing a statement number that was never sent" do
      expect(build_from(one_case(question(number: 99)))[:cases]).to be_empty
      expect(build_from(one_case(question(number: 0)))[:cases]).to be_empty
    end

    it "keeps the good questions in a case that also had a bad one" do
      built = build_from(one_case(question, question(quote: "inventado")))

      expect(built[:cases].sole.questions.size).to eq(1)
      expect(built[:rejected]).to eq(1)
    end

    it "skips a case with no vignette or no questions" do
      payload = { "cases" => [
        { "stem" => "", "questions" => [question] },
        { "stem" => "Paciente.", "questions" => [] }
      ] }

      expect(build_from(payload)[:cases]).to be_empty
    end
  end

  # A case that reads "Pregunta 1, Pregunta 3" to a student is a bug the reviewer sees
  # before the student does.
  it "numbers the questions that survived, not the ones the model sent" do
    kase = build_from(one_case(question, question(number: 99), question))[:cases].sole

    expect(kase.questions.pluck(:position)).to eq([1, 2])
  end

  describe "difficulty" do
    def difficulty_for(grade)
      recommendation.update!(grade: grade)
      build_from(one_case(question))[:cases].sole.difficulty
    end

    it "calls a case from strong evidence an easier item and one from weak evidence a harder one" do
      expect(difficulty_for("A")).to eq("low")
      expect(difficulty_for("D")).to eq("high")
    end

    it "sits in the middle for a grade it does not recognise, or no grade at all" do
      expect(difficulty_for("2b")).to eq("medium")
      expect(difficulty_for(nil)).to eq("medium")
    end
  end

  describe "a figure" do
    let(:pointing) do
      create(
        :recommendation, guideline_section: section,
        text: "Se recomienda estratificar el riesgo según el cuadro 1."
      )
    end
    let(:image) { create(:clinical_image, :stored, guideline_section: section, label: "CUADRO 1") }
    let(:window) { [recommendation, pointing] }

    it "goes on the case that cited the statement pointing at it" do
      built = build_from(
        one_case(question(number: 2, quote: "estratificar el riesgo")),
        recommendations: window, figure: [pointing, image]
      )

      expect(built[:cases].sole.clinical_image).to eq(image)
    end

    # It is told which statement to use, but nothing forces it to comply.
    it "is left off when the model wrote about something else" do
      built = build_from(one_case(question), recommendations: window, figure: [pointing, image])

      expect(built[:cases].sole.clinical_image).to be_nil
    end
  end
end

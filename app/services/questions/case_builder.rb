# Turns the JSON a model returned into saved clinical cases, keeping only what passes.
#
# Nothing the model says is trusted. Every question must name the recommendation it used
# and quote a span of it, and that quote is checked against the stored text before the row
# is written. A question that fails is dropped and counted, never repaired — a citation we
# had to fix is a citation the model did not actually have.
module Questions
  class CaseBuilder < ApplicationService
    # Seeded from the strength of the evidence behind the case: a strong recommendation
    # makes a more clear-cut item than a weak one. Recalibrated from real answer data
    # later, which is what CIFRHS itself does.
    STRONG_GRADES = /\A(A|1\+{1,2}|I{1,2}[ab]?|alta|fuerte)\b/i
    WEAK_GRADES = /\A(D|4|IV|muy baja|baja|d[ée]bil)\b/i

    # `recommendations` must be in the order the prompt numbered them, since that number
    # is how the model says which one it used.
    def initialize(payload, guideline:, recommendations:, run: nil, locale: "es")
      super()
      @payload = payload
      @guideline = guideline
      @recommendations = recommendations
      @run = run
      @locale = locale
      @rejected = 0
    end

    def call
      cases = Array(payload["cases"]).filter_map { |attributes| build_case(attributes) }

      success(cases: cases, rejected: rejected)
    end

    private

    attr_reader :payload, :guideline, :recommendations, :run, :locale, :rejected

    def build_case(attributes)
      questions = Array(attributes["questions"])
      return if attributes["stem"].blank? || questions.empty?

      kase = ClinicalCase.new(
        stem: attributes["stem"], guideline: guideline, generation_run: run,
        topic: topic, specialty: topic&.branch&.specialty, source: "gpc_generated", locale: locale
      )
      built = questions.filter_map.with_index(1) { |question, position| build_question(kase, question, position) }
      return if built.empty?

      # A rejected question must not leave a hole. Positions number what survived, not
      # what the model sent, or a case reads "Pregunta 1, Pregunta 3" to a student.
      built.each.with_index(1) { |question, position| question.position = position }

      kase.difficulty = difficulty_for(built)
      kase.save!
      kase
    end

    def build_question(kase, attributes, position)
      options = Array(attributes["options"])
      question = kase.questions.build(
        position: position, text: attributes["text"], explanation: attributes["explanation"],
        recommendation: cited(attributes["recommendation"]), source_quote: attributes["quote"]
      )
      options.each.with_index(1) do |option, order|
        question.answer_options.build(position: order, text: option["text"], correct: option["correct"] ? true : false)
      end

      return question if usable?(question, options)

      @rejected += 1
      kase.questions.delete(question)
      nil
    end

    # The model numbers the statements itself, so a number outside the list means it
    # invented the reference. Nil, and usable? drops the question.
    def cited(number)
      index = number.to_i - 1
      recommendations[index] unless index.negative?
    end

    # Four options, exactly one of them correct, and a quote that really is in the cited
    # recommendation. The quote check lives on Question so that nothing can write a
    # question that skips it; this only decides whether to keep the row at all.
    def usable?(question, options)
      return false if question.recommendation.nil?
      return false unless options.size == Question::OPTION_COUNT
      return false unless options.count { |option| option["correct"] } == 1

      question.valid?
    end

    # Only called with questions that passed usable?, so every one has a recommendation;
    # a missing grade is the only gap, and filter_map drops it.
    def difficulty_for(questions)
      grades = questions.filter_map { |question| question.recommendation.grade }
      return "low" if grades.any? { |grade| grade.match?(STRONG_GRADES) }
      return "high" if grades.any? { |grade| grade.match?(WEAK_GRADES) }

      "medium"
    end

    def topic
      return @topic if defined?(@topic)

      @topic = guideline.main_topic
    end
  end
end

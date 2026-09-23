# The second opinion, from another model family, on a case the generator already wrote.
#
# Every automated structural check — valid JSON, four options, exactly one correct, a
# citation that survives the substring gate — passes at 100% on every provider measured.
# None of them can see whether the option marked correct is the one the recommendation
# actually supports, and that is the failure a cheap generator would produce.
#
# So the verifier is not asked to grade the generator's answer. It is asked to answer the
# question itself, from the recommendation alone, and the verdict comes from whether it
# lands on the same option. A model shown which answer is marked correct agrees with it;
# a model asked to choose has to disagree out loud.
module Questions
  class Verifier < ApplicationService
    MAX_TOKENS = 2_000

    # Worst wins. A case is a unit — exams select whole cases — so one question whose
    # answer another family disputes holds the whole case back.
    SEVERITY = %w[unsupported ambiguous supported].freeze

    # Options go out lettered, as on the real exam. Numbered options were answered
    # zero-based often enough to record a verifier that agreed as one that disputed.
    LETTERS = %w[A B C D].freeze

    def initialize(clinical_case, run: nil)
      super()
      @clinical_case = clinical_case
      @run = run
    end

    def call
      return failure("El caso no tiene preguntas verificables") if questions.empty?

      completion = Llm::Completion.call(role: :verifier, prompt: prompt, max_tokens: MAX_TOKENS)
      return failure(completion.errors) unless completion.success?

      judgements = parse(completion.payload[:content])
      return failure("El verificador no devolvió JSON legible") if judgements.nil?

      record(completion.payload)
      success(verdict: apply(judgements), notes: clinical_case.verification_notes)
    end

    def context_for_logging
      { clinical_case_id: clinical_case.id }
    end

    private

    attr_reader :clinical_case, :run

    # Only questions that carry both a citation and a marked answer can be judged; a
    # question missing either was never verifiable and is not evidence against the case.
    def questions
      @questions ||= clinical_case.questions.select do |question|
        question.recommendation.present? && question.correct_option.present?
      end
    end

    def prompt
      <<~TEXT
        Eres médico revisor de reactivos del ENARM. Vas a responder preguntas de opción
        múltiple usando ÚNICAMENTE la recomendación de la guía de práctica clínica que se
        incluye con cada una. No uses conocimiento propio para elegir: si la recomendación
        no basta para decidir, dilo.

        Caso clínico:
        #{clinical_case.stem}

        #{questions.map.with_index(1) { |question, index| block_for(question, index) }.join("\n")}
        Para cada pregunta devuelve la letra de la opción que la recomendación respalda, y
        si la recomendación alcanza para decidirla.

        Devuelve SOLO JSON, sin markdown:
        {"questions":[{"question":1,"option":"B","decidable":true,"note":"..."}]}
      TEXT
    end

    def block_for(question, index)
      options = question.answer_options.each_with_index.map { |option, index| "  #{LETTERS[index]}) #{option.text}" }

      <<~TEXT
        Pregunta #{index}: #{question.text}
        #{options.join("\n")}
        Recomendación: #{question.recommendation.text.squish}
      TEXT
    end

    def parse(content)
      JSON.parse(content.to_s.strip.sub(/\A```(?:json)?/, "").sub(/```\z/, "").strip)
    rescue JSON::ParserError
      nil
    end

    def apply(judgements)
      verdicts = Array(judgements["questions"]).filter_map { |judgement| judge(judgement) }
      verdict = worst(verdicts)

      clinical_case.update!(
        verification_verdict: verdict, verified_at: Time.current,
        verification_notes: verdicts.map(&:last).compact_blank.join("\n").presence
      )
      verdict
    end

    # Silence from the second opinion is not assent: a verifier that answered two of a
    # case's three questions has not cleared the third, so the case cannot pass on what
    # it did say.
    def worst(verdicts)
      verdict = SEVERITY.find { |candidate| verdicts.any? { |row| row.first == candidate } }
      return "ambiguous" if verdict.nil? || (verdict == "supported" && verdicts.size < questions.size)

      verdict
    end

    # A question the verifier never answered is not a pass. Silence from the second
    # opinion is not assent, and the case waits rather than going live unexamined.
    #
    # Only a readable choice of a different option is a dispute. A verifier that says the
    # statement cannot settle the question has guessed its option, and one whose answer
    # cannot be read has said nothing; both leave the case ambiguous, for a person to read.
    def judge(judgement)
      question = questions[judgement["question"].to_i - 1]
      return if question.nil?

      chosen = option_at(question, judgement["option"])
      note = ["#{question.position}.", judgement["note"]].compact_blank.join(" ")

      return ["ambiguous", note] if !judgement["decidable"] || chosen.nil?
      return ["unsupported", note] unless chosen.correct?

      ["supported", nil]
    end

    def option_at(question, letter)
      index = LETTERS.index(letter.to_s.strip.upcase)
      question.answer_options[index] if index
    end

    def record(usage)
      return if run.nil?

      run.increment!(:input_tokens, usage[:input_tokens])
      run.increment!(:output_tokens, usage[:output_tokens])
      run.increment!(:cost_usd, usage[:cost_usd])
      run.increment!(:attempts, 1)
    end
  end
end

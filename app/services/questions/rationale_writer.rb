# Writes, for a case generated before options carried one, why each distractor is not the
# answer — the explanation a student who chose it actually needs.
#
# The model is shown the whole question with the right answer marked, the statement it
# cites, and the rest of the guideline's statements: the most instructive distractors are
# right somewhere else in the same guideline, and it can only say where if it can read
# it. It writes nothing about the correct option, whose explanation already exists.
module Questions
  class RationaleWriter < ApplicationService
    MAX_TOKENS = 3_000

    # Enough of the guideline to find where a distractor does apply, without sending a
    # whole anexo for every case.
    CONTEXT_STATEMENTS = 40

    LETTERS = Verifier::LETTERS

    def initialize(clinical_case, run: nil)
      super()
      @clinical_case = clinical_case
      @run = run
    end

    def call
      return failure("El caso no tiene preguntas con recomendación citada") if questions.empty?

      completion = Llm::Completion.call(role: :generator, prompt: prompt, max_tokens: MAX_TOKENS)
      return failure(completion.errors) unless completion.success?

      written = parse(completion.payload[:content])
      return failure("El modelo no devolvió JSON legible") if written.nil?

      record(completion.payload)
      success(written: apply(written))
    end

    def context_for_logging
      { clinical_case_id: clinical_case.id }
    end

    private

    attr_reader :clinical_case, :run

    def questions
      @questions ||= clinical_case.questions.includes(:answer_options, :recommendation).select(&:recommendation)
    end

    def prompt
      <<~TEXT
        Eres médico revisor de reactivos del ENARM. Cada pregunta ya tiene su respuesta
        correcta marcada con (correcta). Tu tarea es explicar los distractores.

        #{Prompt::RATIONALE_INSTRUCTIONS}
        #{language}
        Caso clínico:
        #{clinical_case.stem}

        #{questions.map.with_index(1) { |question, index| block_for(question, index) }.join("\n")}
        Otras recomendaciones de la misma guía, por si algún distractor aplica en otro momento:
        #{context}

        Devuelve SOLO JSON, sin markdown, con una razón por cada distractor (nunca por la correcta):
        {"questions":[{"question":1,"rationales":{"B":"...","C":"...","D":"..."}}]}
      TEXT
    end

    def block_for(question, index)
      options = question.answer_options.each_with_index.map do |option, position|
        "  #{LETTERS[position]}) #{option.text}#{" (correcta)" if option.correct?}"
      end

      <<~TEXT
        Pregunta #{index}: #{question.text}
        #{options.join("\n")}
        Por qué la correcta lo es: #{question.explanation}
        Recomendación citada: #{question.recommendation.text.squish}
      TEXT
    end

    def language
      return "" unless clinical_case.locale == "en"

      "\nEl caso está en inglés: escribe las razones EN INGLÉS.\n"
    end

    def context
      cited = questions.map(&:recommendation_id)
      guideline_id = questions.first.recommendation.guideline_section.guideline_id
      Recommendation.actionable.where(guideline_sections: { guideline_id: guideline_id })
                    .where.not(id: cited).order(:id).limit(CONTEXT_STATEMENTS)
                    .map { |recommendation| "- #{recommendation.text.squish}" }.join("\n")
    end

    def parse(content)
      JSON.parse(content.to_s.strip.sub(/\A```(?:json)?/, "").sub(/```\z/, "").strip)
    rescue JSON::ParserError
      nil
    end

    # Only distractors, only letters that exist, only text that says something. A reply
    # about the correct option or a letter the question does not have is dropped.
    def apply(written)
      Array(written["questions"]).sum do |entry|
        question = questions[entry["question"].to_i - 1]
        next 0 if question.nil? || !entry["rationales"].is_a?(Hash)

        entry["rationales"].sum do |letter, text|
          option = option_at(question, letter)
          next 0 if option.nil? || option.correct? || text.to_s.squish.blank?

          option.update!(rationale: text.to_s.squish)
          1
        end
      end
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

# Turns a batch of a guideline's recommendations into clinical cases.
#
# Nothing the model says is trusted. Every question must name the recommendation it used
# and quote a span of it, and that quote is checked against the stored text in Ruby before
# the row is written. A question that fails is dropped and counted, never repaired — a
# citation we had to fix is a citation the model did not actually have.
module Questions
  class CaseGenerator < ApplicationService
    RECOMMENDATIONS_PER_CALL = 8
    CASES_PER_CALL = 2
    QUESTIONS_PER_CASE = 2
    MAX_TOKENS = 8_000

    # Seeded from the strength of the evidence behind the case: a strong recommendation
    # makes a more clear-cut item than a weak one. Recalibrated from real answer data
    # later, which is what CIFRHS itself does.
    STRONG_GRADES = /\A(A|1\+{1,2}|I{1,2}[ab]?|alta|fuerte)\b/i
    WEAK_GRADES = /\A(D|4|IV|muy baja|baja|d[ée]bil)\b/i

    def initialize(guideline, run: nil, limit: RECOMMENDATIONS_PER_CALL)
      super()
      @guideline = guideline
      @run = run
      @limit = limit
    end

    def call
      return failure("La guía no tiene recomendaciones accionables") if recommendations.empty?

      completion = Llm::Completion.call(role: :generator, prompt: prompt, max_tokens: MAX_TOKENS)
      return failure(completion.errors) unless completion.success?

      payload = parse(completion.payload[:content])
      return failure("El modelo no devolvió JSON legible") if payload.nil?

      cases = persist(payload)
      record(completion.payload, cases)

      success(cases: cases, rejected: @rejected.to_i, tokens: completion.payload[:output_tokens])
    end

    def context_for_logging
      { catalog_key: guideline.catalog_key }
    end

    private

    attr_reader :guideline, :run, :limit

    def recommendations
      @recommendations ||= Recommendation.joins(:guideline_section)
                                         .where(guideline_sections: { guideline_id: guideline.id,
                                                                      kind: GuidelineSection::ACTIONABLE_KINDS }
                                               )
                                         .order(:id)
                                         .limit(limit)
                                         .to_a
    end

    def prompt
      listing = recommendations.map.with_index(1) { |r, i| "#{i}. #{r.text.squish}" }.join("\n")

      <<~TEXT
        Eres redactor de reactivos para el ENARM, el examen nacional de residencias médicas
        en México. Escribes en español de México, con terminología clínica formal.

        A partir de las siguientes recomendaciones de la guía de práctica clínica
        "#{guideline.title}", escribe #{CASES_PER_CALL} casos clínicos.

        Cada caso:
        - Una viñeta clínica de 3 a 5 líneas: edad, sexo, antecedentes relevantes, motivo de
          consulta y hallazgos. Realista, como la de un examen real.
        - #{QUESTIONS_PER_CASE} preguntas sobre ese mismo caso.

        Cada pregunta:
        - Exactamente CUATRO opciones: una correcta y tres distractores plausibles, del tipo
          que elegiría alguien que estudió el tema de forma incompleta. Un distractor
          evidentemente absurdo hace inútil el reactivo.
        - Una explicación breve de por qué la correcta lo es.
        - El número de la recomendación en la que se basa, y una cita textual de esa
          recomendación.

        Sobre la cita: copia un fragmento CONTINUO, palabra por palabra, tal como aparece.
        NUNCA uses puntos suspensivos ni omitas palabras intermedias. Si el fragmento útil
        es largo, cita una parte contigua más corta.

        Devuelve SOLO JSON, sin markdown ni texto alrededor. Las llaves van en inglés y
        los valores en español:
        {"cases":[{"stem":"...","questions":[{"text":"...","explanation":"...",
        "recommendation":1,"quote":"...","options":[{"text":"...","correct":true},
        {"text":"...","correct":false},{"text":"...","correct":false},
        {"text":"...","correct":false}]}]}]}

        Recomendaciones:
        #{listing}
      TEXT
    end

    def parse(content)
      JSON.parse(content.to_s.strip.sub(/\A```(?:json)?/, "").sub(/```\z/, "").strip)
    rescue JSON::ParserError
      nil
    end

    def persist(payload)
      @rejected = 0

      Array(payload["cases"]).filter_map do |attributes|
        build_case(attributes)
      end
    end

    def build_case(attributes)
      questions = Array(attributes["questions"])
      return if attributes["stem"].blank? || questions.empty?

      kase = ClinicalCase.new(
        stem: attributes["stem"], guideline: guideline, generation_run: run,
        topic: guideline.topics.first, specialty: specialty, source: "gpc_generated"
      )
      built = questions.filter_map.with_index(1) { |q, position| build_question(kase, q, position) }

      return if built.empty?

      kase.difficulty = difficulty_for(built)
      kase.save!
      kase
    end

    def build_question(kase, attributes, position)
      options = Array(attributes["options"])
      recommendation = recommendations[attributes["recommendation"].to_i - 1]

      question = kase.questions.build(
        position: position, text: attributes["text"], explanation: attributes["explanation"],
        recommendation: recommendation, source_quote: attributes["quote"]
      )
      options.each_with_index do |option, index|
        question.answer_options.build(
          position: index + 1, text: option["text"],
          correct: option["correct"] ? true : false
        )
      end

      return question if usable?(question, options)

      @rejected += 1
      kase.questions.delete(question)
      nil
    end

    # Four options, exactly one of them correct, and a quote that really is in the cited
    # recommendation. The quote check lives on the model so that nothing can write a
    # question that skips it; this only decides whether to keep the row at all.
    def usable?(question, options)
      # A question that cites a recommendation we never sent has no provenance at all.
      # The model numbers them itself, so an out-of-range number means it invented the
      # reference — and Question#recommendation is optional, so nothing downstream would
      # have caught it.
      return false if question.recommendation.nil?
      return false unless options.size == Question::OPTION_COUNT
      return false unless options.count { |option| option["correct"] } == 1

      question.valid?
    end

    def specialty
      @specialty ||= guideline.topics.first&.branch&.specialty
    end

    # Only ever called with questions that passed usable?, which requires a recommendation,
    # so there is none to guard against here — only a missing grade, which filter_map drops.
    def difficulty_for(questions)
      grades = questions.filter_map { |q| q.recommendation.grade }
      return "medium" if grades.empty?
      return "low" if grades.any? { |grade| grade.match?(STRONG_GRADES) }
      return "high" if grades.any? { |grade| grade.match?(WEAK_GRADES) }

      "medium"
    end

    def record(usage, cases)
      return if run.nil?

      run.increment!(:input_tokens, usage[:input_tokens])
      run.increment!(:output_tokens, usage[:output_tokens])
      run.increment!(:cases_created, cases.size)
      run.increment!(:attempts, cases.size + @rejected.to_i)
      run.increment!(:rejections, @rejected.to_i)
    end
  end
end

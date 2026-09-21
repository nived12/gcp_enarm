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
    MAX_TOKENS = 12_000

    # A real ENARM vignette carries a whole patient — comorbidities with durations,
    # complete vitals with units, a systematic examination — and then asks about one
    # part of it. Ours were about 45 words with every fact pointing at the answer, which
    # a doctor reading them spotted immediately as too easy. `full_workup` is that whole
    # patient; `focused` stays short, because not every real item is long either.
    DETAIL_LEVELS = %i[focused full_workup].freeze

    # Questions per case. The convocatoria says two to three; a longer vignette earns
    # the third, since there is more in it to ask about.
    QUESTIONS_BY_DETAIL = { focused: 2, full_workup: 3 }.freeze

    # The real exam is written in Spanish with a small English share, so the bank has to
    # be too. Kept as a fraction of *cases*, not questions, because a case and its
    # questions must be in one language.
    ENGLISH_SHARE = 0.08

    # Roughly one item in six carries a figure. A real exam shows far fewer images than a
    # competitor's marketing suggests, and this number is an estimate until a doctor has
    # read a batch and said otherwise.
    IMAGE_SHARE = 0.15

    # Seeded from the strength of the evidence behind the case: a strong recommendation
    # makes a more clear-cut item than a weak one. Recalibrated from real answer data
    # later, which is what CIFRHS itself does.
    STRONG_GRADES = /\A(A|1\+{1,2}|I{1,2}[ab]?|alta|fuerte)\b/i
    WEAK_GRADES = /\A(D|4|IV|muy baja|baja|d[ée]bil)\b/i

    def initialize(guideline, run: nil, limit: RECOMMENDATIONS_PER_CALL,
                   detail: :focused, locale: "es", with_image: false)
      super()
      @guideline = guideline
      @run = run
      @limit = limit
      @detail = DETAIL_LEVELS.include?(detail) ? detail : :focused
      @locale = locale
      @with_image = with_image
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

    attr_reader :guideline, :run, :limit, :detail, :locale, :with_image

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
        en México. Escribes con terminología clínica formal.

        A partir de las siguientes recomendaciones de la guía de práctica clínica
        "#{guideline.title}", escribe #{CASES_PER_CALL} casos clínicos, cada uno con
        #{questions_per_case} preguntas de opción múltiple.

        #{vignette_instructions}

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
        #{language_instruction}#{image_instructions}
        Devuelve SOLO JSON, sin markdown ni texto alrededor. Las llaves van en inglés:
        {"cases":[{"stem":"...","questions":[{"text":"...","explanation":"...",
        "recommendation":1,"quote":"...","options":[{"text":"...","correct":true},
        {"text":"...","correct":false},{"text":"...","correct":false},
        {"text":"...","correct":false}]}]}]}

        Recomendaciones:
        #{listing}
      TEXT
    end

    def questions_per_case
      QUESTIONS_BY_DETAIL.fetch(detail)
    end

    # The difference a doctor asked for. A real vignette presents the whole patient and
    # then asks about one part of it; ours presented only the part that answered the
    # question, which makes the item easier than the exam it is simulating.
    #
    # The extra material is realistic completeness, not misdirection: normal findings and
    # background history belong in a real chart, and deciding what matters is the skill
    # being tested. Inventing misleading findings would be a different thing entirely.
    def vignette_instructions
      if detail == :full_workup
        <<~TEXT.strip
          La viñeta debe presentar al paciente COMPLETO, como en el examen real (150 a 200
          palabras):
          - Edad, sexo y antecedentes con su duración y tratamiento ("diabetes mellitus tipo 2
            de 12 años en manejo irregular", "hipertensión controlada con IECA").
          - Motivo de consulta con inicio, duración y evolución precisas.
          - Signos vitales COMPLETOS con unidades: TA, FC, FR, SatO2, temperatura.
          - Exploración física sistemática, incluyendo hallazgos normales.
          - Cuando la recomendación lo justifique, resultados de laboratorio con sus valores.

          Incluye datos clínicos reales que NO apuntan a la respuesta: antecedentes de fondo,
          hallazgos normales, cifras dentro de rango. No son distractores ni pistas falsas —
          son lo que trae cualquier paciente real, y distinguir lo relevante es justo lo que
          el reactivo evalúa. Nunca inventes hallazgos que contradigan el diagnóstico.

          Las #{questions_per_case} preguntas se apoyan en el mismo caso, cada una sobre un
          aspecto distinto.
        TEXT
      else
        <<~TEXT.strip
          La viñeta es breve y centrada (60 a 90 palabras): edad, sexo, antecedentes
          relevantes, motivo de consulta y los hallazgos necesarios. No todo reactivo del
          examen real es largo.
        TEXT
      end
    end

    # The figure has to be chosen before the prompt is written, not attached to a
    # finished case: a vignette that was not written towards an image reads as a vignette
    # with a picture stapled to it, and the real exam does not do that.
    #
    # The model is not shown the image and must not be asked about what is in it. What it
    # is told is that the recommendation it is citing sends the reader to a figure, and
    # that the figure will be on screen — so the item still rests entirely on the quoted
    # text, which is the only thing the citation gate can check.
    def image_instructions
      return "" if figure.nil?

      recommendation, image = figure
      number = recommendations.index(recommendation) + 1

      "\nUno de los casos debe apoyarse en la recomendación #{number}, que remite a " \
        "«#{[image.label, image.caption].compact_blank.join(": ")}». Esa figura se mostrará " \
        "junto al caso, así que la viñeta debe llegar de forma natural a consultarla y una " \
        "de sus preguntas debe referirse a ella.\n" \
        "No describas el contenido de la figura ni inventes cifras, filas ni valores suyos: " \
        "no la estás viendo. La pregunta debe poder responderse con la recomendación citada.\n"
    end

    def figure
      return @figure if defined?(@figure)

      @figure = with_image ? ClinicalImage.cited_by(recommendations) : nil
    end

    def language_instruction
      return "" unless locale == "en"

      "\nEscribe la viñeta, las preguntas, las opciones y las explicaciones EN INGLÉS. " \
        "La cita textual se queda en español, tal como aparece en la recomendación.\n"
    end

    def parse(content)
      JSON.parse(content.to_s.strip.sub(/\A```(?:json)?/, "").sub(/```\z/, "").strip)
    rescue JSON::ParserError
      nil
    end

    def persist(payload)
      @rejected = 0

      cases = Array(payload["cases"]).filter_map { |attributes| build_case(attributes) }
      attach_figure(cases)
      cases
    end

    # Only if the model actually cited the recommendation that points at the figure. It
    # is told which one to use, but a case that went elsewhere gets no image rather than
    # an image belonging to something it never mentions.
    def attach_figure(cases)
      return if figure.nil?

      recommendation, image = figure
      cited = cases.find do |kase|
        kase.questions.any? { |question| question.recommendation_id == recommendation.id }
      end
      cited&.update!(clinical_image: image)
    end

    def build_case(attributes)
      questions = Array(attributes["questions"])
      return if attributes["stem"].blank? || questions.empty?

      kase = ClinicalCase.new(
        stem: attributes["stem"], guideline: guideline, generation_run: run,
        topic: guideline.topics.first, specialty: specialty, source: "gpc_generated",
        locale: locale
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

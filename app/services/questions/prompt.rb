# The words a generation call sends the model.
#
# Kept apart from the call itself because this is the part a doctor reviews and the part
# most likely to change after a batch is read: it should read top to bottom as the text it
# produces, with nothing about HTTP, JSON or rows in between.
module Questions
  class Prompt
    CASES = 2

    # A real ENARM vignette carries a whole patient — comorbidities with durations,
    # complete vitals with units, a systematic examination — and then asks about one
    # part of it. Ours were about 45 words with every fact pointing at the answer, which
    # a doctor reading them spotted immediately as too easy. `full_workup` is that whole
    # patient; `focused` stays short, because not every real item is long either.
    #
    # Questions per case: the convocatoria says two to three, and a longer vignette earns
    # the third, since there is more in it to ask about.
    QUESTIONS_BY_DETAIL = { focused: 2, full_workup: 3 }.freeze
    DETAIL_LEVELS = QUESTIONS_BY_DETAIL.keys.freeze

    # The convocatoria (§9.1) examines "competencias cognitivas contextualizadas en casos
    # clínicos enfocados en Salud Pública, Urgencias y Medicina Familiar" — the three
    # contexts are where a case happens, the four troncales are what it is about. The
    # model picks the setting that fits the recommendation; a fixed rotation would put a
    # neonatal resuscitation in a family-medicine consult.
    SETTING_INSTRUCTIONS = <<~TEXT.strip
      Sitúa cada caso en uno de los tres contextos del examen: la consulta de medicina
      familiar en el primer nivel, un servicio de urgencias, o una situación de salud
      pública (tamizaje, vacunación, brote, vigilancia epidemiológica, prevención en la
      comunidad). Elige el que encaje con la recomendación, y si escribes dos casos, que no
      ocurran en el mismo contexto cuando el tema lo permita. No sitúes el caso en una sala
      de hospitalización genérica.
    TEXT

    # `figure` is a [recommendation, image] pair from ClinicalImage.cited_by, or nil.
    # An unknown detail level falls back to focused rather than failing the call.
    def initialize(guideline, recommendations, detail: :focused, locale: "es", figure: nil)
      @guideline = guideline
      @recommendations = recommendations
      @detail = DETAIL_LEVELS.include?(detail) ? detail : :focused
      @locale = locale
      @figure = figure
    end

    def to_s
      <<~TEXT
        Eres redactor de reactivos para el ENARM, el examen nacional de residencias médicas
        en México. Escribes con terminología clínica formal.

        A partir de las siguientes recomendaciones de la guía de práctica clínica
        "#{guideline.title}", escribe #{CASES} casos clínicos, cada uno con
        #{questions_per_case} preguntas de opción múltiple.

        #{vignette_instructions}

        #{SETTING_INSTRUCTIONS}

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
        #{language_instructions}#{figure_instructions}
        Devuelve SOLO JSON, sin markdown ni texto alrededor. Las llaves van en inglés:
        {"cases":[{"stem":"...","questions":[{"text":"...","explanation":"...",
        "recommendation":1,"quote":"...","options":[{"text":"...","correct":true},
        {"text":"...","correct":false},{"text":"...","correct":false},
        {"text":"...","correct":false}]}]}]}

        Recomendaciones:
        #{listing}
      TEXT
    end

    private

    attr_reader :guideline, :recommendations, :detail, :locale, :figure

    # Numbered from 1. The model cites a statement by this number, and
    # Questions::CaseBuilder maps it back to the row.
    def listing
      recommendations.map.with_index(1) { |recommendation, i| "#{i}. #{recommendation.text.squish}" }.join("\n")
    end

    def questions_per_case
      QUESTIONS_BY_DETAIL.fetch(detail)
    end

    # The extra material in a full workup is realistic completeness, not misdirection:
    # normal findings and background history belong in a real chart, and deciding what
    # matters is the skill being tested. Inventing misleading findings would be a
    # different thing entirely.
    def vignette_instructions
      return <<~TEXT.strip if detail == :focused
        La viñeta es breve y centrada (60 a 90 palabras): edad, sexo, antecedentes
        relevantes, motivo de consulta y los hallazgos necesarios. No todo reactivo del
        examen real es largo.
      TEXT

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
    end

    # The quote stays in Spanish so the citation gate can still find it in the statement.
    def language_instructions
      return "" unless locale == "en"

      "\nEscribe la viñeta, las preguntas, las opciones y las explicaciones EN INGLÉS. " \
        "La cita textual se queda en español, tal como aparece en la recomendación.\n"
    end

    # The model is not shown the image and must not be asked about what is in it. What it
    # is told is that the recommendation it is citing sends the reader to a figure, and
    # that the figure will be on screen — so the item still rests entirely on the quoted
    # text, which is the only thing the citation gate can check.
    def figure_instructions
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
  end
end

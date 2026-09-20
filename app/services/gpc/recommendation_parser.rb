# Splits a section body into the graded statements it contains.
#
# The shape is always the same: a <div class="separador"> carrying the grading strip,
# then the statement's own markup until the next separador. Everything between two
# separadores belongs to the first one, including lists and tables, so the walk is
# over siblings rather than a CSS query.
module Gpc
  class RecommendationParser < ApplicationService
    # The grading strip is written by hand and its word order is not stable — most
    # read "1++ NICE Hong K, 2021" but a few read "SIGN D Taylor M, 2015", and some
    # grades are phrases ("Fuerte a favor", "Muy baja"). The scale name is the only
    # dependable anchor, so grade and citation are read relative to it. Longest first,
    # so ACC/AHA/ESC is not matched as ESC.
    #
    # Sampled from every guideline in the live catalog on 2026-09-20; ~1.5% of strips
    # name no scale we recognise, and those keep #label with the other three nil.
    #
    # The scale is named as an acronym — NICE, GRADE, SIGN, ACC/AHA/ESC, ESCMID. Which
    # society wrote it is open-ended (the live catalog cites 30+), so the scale is
    # recognised by shape rather than by a list that would always be one guideline
    # behind: three or more capitals, optionally joined by / or -.
    SCALE_SHAPE = %r{\A[A-Z][A-Z0-9]*(?:[/-][A-Z0-9]+)*\z}

    # Grades written the same way, which the shape alone cannot tell apart. Unlike the
    # societies this set really is closed: evidence levels (the AHA's B-NR, C-LD), the
    # good-practice marker, and the GRADE strength and certainty words in caps.
    # Recommendation classes, written as Roman numerals: I, IIa, III. Only the ones in
    # capitals reach here, and no scale acronym is spelled from these letters alone.
    ROMAN_GRADE = /\A[IVX]+[AB]?\z/

    # Some guidelines write "III Escala ESCMID …". The word is a label for what
    # follows, not part of the grade.
    SCALE_LABEL_WORD = /\Aescala\z/i

    NON_SCALE_TOKENS = %w[
      PBP GPP BPP
      B-R B-NR C-LD C-EO
      FUERTE DÉBIL DEBIL CONDICIONAL FAVOR CONTRA
      ALTA ALTO MODERADA MODERADO BAJA BAJO MUY
    ].freeze

    # Only used when the strip leads with the scale; a longer token in that position
    # is part of the citation, not a grade.
    SHORT_GRADE = /\A([A-D]|[1-4]\+{0,2}|[1-4][A-C])\z/

    def initialize(body)
      super()
      @body = body
    end

    def call
      success(statements)
    end

    private

    attr_reader :body

    def statements
      position = 0

      separador_nodes.filter_map do |node|
        text = statement_text_after(node)
        label = node.text.squish
        next if text.blank? || label.blank?

        position += 1
        parse_label(label).merge(text: text, position: position)
      end
    end

    def separador_nodes
      Nokogiri::HTML.fragment(body).css("div.separador")
    end

    # Between two separadores the site emits flat <p> and <li> siblings — no tables,
    # no wrappers — so one sibling is one line. Joining with newlines keeps a list of
    # eight items from reading as one run-on sentence.
    def statement_text_after(separador)
      parts = []
      node = separador.next_sibling

      while node && !separador?(node)
        parts << node.text.squish
        node = node.next_sibling
      end

      parts.compact_blank.join("\n")
    end

    def separador?(node)
      node.element? && node.classes.include?("separador")
    end

    def parse_label(label)
      tokens = label.split(" ")
      index = tokens.index { |token| scale_for(token) }
      return { label: label, grade: nil, scale: nil, citation: nil } if index.nil?

      grade = tokens[0...index].grep_v(SCALE_LABEL_WORD)
      citation = tokens[(index + 1)..]
      grade = [citation.shift] if grade.empty? && short_grade?(citation.first)

      {
        label: label,
        grade: grade.join(" ").presence,
        scale: scale_for(tokens[index]),
        citation: citation.join(" ").presence
      }
    end

    def short_grade?(token)
      token.to_s.match?(SHORT_GRADE)
    end

    # Author initials are capitals too, so a two-letter token is never a scale —
    # "Dhatariya KK, 2020" must not read as a scale called KK.
    def scale_for(token)
      normalized = token.gsub(/[[:punct:]]+\z/, "")
      return unless normalized.length >= 3
      return unless normalized.match?(SCALE_SHAPE)
      return if NON_SCALE_TOKENS.include?(normalized)
      return if ROMAN_GRADE.match?(normalized)

      normalized
    end
  end
end

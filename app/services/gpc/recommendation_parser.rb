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
    # Only scales actually seen in the live catalog. PBP ("punto de buena práctica")
    # looks like one but is a grade — it appears as "PBP ESPEN Volkert D, 2022" — and
    # the archive corpus will add its own, SHEKELLE above all. Adding one is safe
    # because #label keeps the strip whole either way.
    SCALES = [
      "ACC/AHA/ESC", "ESHRE", "ESPEN", "CHEST", "GRADE",
      "GEMA", "GINA", "IDSA", "NICE", "SEGG", "SIGN", "ESA"
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

      grade = tokens[0...index]
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

    def scale_for(token)
      normalized = token.gsub(/[[:punct:]]+\z/, "").upcase
      SCALES.find { |scale| scale == normalized }
    end
  end
end

module Gpc
  module ArchiveTable
    # The grading column's vocabulary, and how to read a row's label once it is collected:
    # "III (Shekelle,1999) Humes, 2008", "Ia [E: Shekelle] Matheson, 2007",
    # "ALTO GRADE Turc G, 2019", "Punto de Buena Práctica". The grade leads, the scale is
    # the first thing that names one, and what is left is the citation.
    class GradingLabel
      # Case matters for the letter grades: a justified line routinely ends in "a".
      GRADE_LEVEL = /\A(?:(?:I{1,3}|IV|V)(?:[- ]?[a-cA-C])?|[1-4](?:\+{1,2}|-|[a-cA-C])?|[A-D][+-]?)\z/
      GRADE_PHRASE = /\A(?:(?:muy\s+)?(?:alt|moderad|baj)[ao]s?(?:\s+calidad)?|fuerte|d[ée]bil|condicional|
                      (?:punto\s+de\s+)?buena(?:\s+pr[áa]ctica)?|pr[áa]ctica|PBP)\z/ix
      GRADE_WORDS = Regexp.union(GRADE_LEVEL, GRADE_PHRASE)
      EVIDENCE_SYMBOLS = /[⨁⊕◯○]/
      SHEKELLE = /[\[(]\s*(?:[ER]\s*:\s*)?(Shekelle(?:\s+modificada)?)[^\])]*[\])]/i

      # A scale is recognised by shape, with the vocabulary the live parser already
      # learned the hard way.
      def self.scale_name(token)
        cleaned = token.delete("[]()").sub(/\A[ER]\s*:\s*/, "").squish
        cleaned if cleaned.length >= 3 && cleaned.match?(RecommendationParser::SCALE_SHAPE) &&
                   !RecommendationParser::NON_SCALE_TOKENS.include?(cleaned) &&
                   !cleaned.match?(RecommendationParser::ROMAN_GRADE)
      end

      def self.parse(label, kind)
        new(label, kind).to_h
      end

      def initialize(label, kind)
        @label = label
        @kind = kind
      end

      def to_h
        return { grade: "PBP", scale: nil, citation: nil } if good_practice?

        scale_match = label.match(SHEKELLE) || label.match(/\b(Shekelle)\b/i)
        tokens = (scale_match ? label.sub(scale_match[0], " ") : label).split
        scale = scale_match ? "Shekelle" : take_scale(tokens)
        grade = leading_grade(tokens)

        { grade: grade, scale: scale, citation: tokens.join(" ").delete("[]").squish.presence }
      end

      private

      attr_reader :label, :kind

      def good_practice?
        kind == "good_practice" && (label == "PBP" || label.match?(/buena\s+pr[áa]ctica/i))
      end

      def take_scale(tokens)
        index = tokens.index { |token| self.class.scale_name(token) }
        self.class.scale_name(tokens.delete_at(index)) if index
      end

      # The grade usually leads, sometimes behind a word naming it ("Nivel 3", "Clase I").
      # When a row's cut put the citation first, the grade follows the citation's year.
      def leading_grade(tokens)
        tokens.shift if tokens.first.to_s.match?(/\A(?:nivel|grado|clase)\z/i) && tokens[1].to_s.match?(GRADE_WORDS)
        return tokens.shift(2).join(" ") if tokens.size > 1 && tokens.first(2).join(" ").match?(GRADE_PHRASE)
        return tokens.shift if tokens.first.to_s.match?(GRADE_WORDS)

        symbols = tokens.take_while { |token| token.match?(EVIDENCE_SYMBOLS) }
        return tokens.shift(symbols.size).join(" ") if symbols.any?

        index = tokens.each_index.find { |i| i.positive? && trailing_grade?(tokens, i) }
        tokens.delete_at(index) if index
      end

      # A letter grade is also an author's initial ("Smith D, 2010"), so a lone letter
      # only counts straight after a year or a closing mark. Longer grades are unambiguous.
      def trailing_grade?(tokens, index)
        token = tokens[index]
        return true if token.length > 1 && token.match?(GRADE_LEVEL)

        token.match?(/\A[A-D]\z/) && tokens[index - 1].match?(/[\d.)\]]\z/)
      end
    end
  end
end

# Leaves out a heading whose letters extraction lost. The bold type of some 2010–2013 IMSS
# PDFs comes out as "4.4 Vigil n i a ma te na" or "4.2.1 Tratami ento no quirúrgi co"; the
# characters underneath are gone, so the heading cannot be repaired, only withheld — a
# citation that shows the guideline without it beats one that shows nonsense.
#
# A heading is damaged when two or more of its lowercase words are either not words of the
# corpus (the recommendations' own text, as for Gpc::TitleRepairer) or scraps of one or
# two letters that are not Spanish short words. Both signals are needed: "ma", "te", "n"
# and "Na" occur in the corpus as symbols and doses, so the scraps of "Vigil n i a ma te
# na" pass for words. Words in capitals are not judged, so acronyms and headings set in
# capitals ("ESCALA AAO-HNSF Y JKMS") stay.
module Gpc
  class HeadingCleaner
    MIN_COUNT = 3
    DAMAGED_WORDS = 2
    SHORT_WORDS = %w[a al de del e el en la las lo los ni no o por se su u un y].freeze

    def initialize(vocabulary)
      @vocabulary = vocabulary
    end

    def call(heading)
      heading unless damaged?(heading)
    end

    private

    attr_reader :vocabulary

    def damaged?(heading)
      heading.to_s.scan(/\p{L}+/).count { |word| word.match?(/\p{Ll}/) && suspect?(word) } >= DAMAGED_WORDS
    end

    def suspect?(word)
      return !SHORT_WORDS.include?(word) if word.size <= 2 && word == word.downcase

      vocabulary[word.downcase] < MIN_COUNT
    end
  end
end

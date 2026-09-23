# Puts back the space extraction dropped between a word and the short word after or
# before it: "Tratamientode" → "Tratamiento de", "laataxia" → "la ataxia". About forty
# archived titles carry one, and a student reads the title on every citation.
#
# A token is split only when it is not a word of the corpus itself and both halves are:
# the vocabulary is the recommendations' own text, where these welds are rare, rather
# than the titles, where "Tratamientode" repeats often enough to look like a word.
module Gpc
  class TitleRepairer
    SHORT_WORDS = %w[de del la las los el en y o con por para a al lo].freeze
    MIN_COUNT = 5
    MIN_PART = 4

    def self.vocabulary
      Recommendation.pluck(:text).each_with_object(Hash.new(0)) do |text, counts|
        text.to_s.downcase.scan(/\p{L}+/) { |word| counts[word] += 1 }
      end
    end

    def initialize(vocabulary)
      @vocabulary = vocabulary
    end

    def call(title)
      title.gsub(/\p{L}+/) { |token| split(token) || token }
    end

    private

    attr_reader :vocabulary

    def split(token)
      word = token.downcase
      # Capitals are cover display type ("ACONDICIONAR"), not a welded pair.
      return if token == token.upcase || word?(word)

      SHORT_WORDS.each do |short|
        rest = word.delete_suffix(short)
        return "#{token[0, rest.size]} #{token[rest.size..]}" if rest != word && joinable?(rest, short)

        rest = word.delete_prefix(short)
        return "#{token[0, short.size]} #{token[short.size..]}" if rest != word && word?(rest) && rest.size >= MIN_PART
      end
      nil
    end

    # "Coordinadora" is a word, not "Coordinador a": a feminine -ora never loses an "a".
    def joinable?(rest, short)
      word?(rest) && rest.size >= MIN_PART && !(short == "a" && rest.end_with?("or"))
    end

    def word?(word)
      vocabulary[word] >= MIN_COUNT
    end
  end
end

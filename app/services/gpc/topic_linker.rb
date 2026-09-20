# Decides which topics each guideline is about, by matching the topic's names against
# the guideline's title.
#
# This replaces the hand curation Dr. Re's temario depends on, and it is why the taxonomy
# survives CENETEC republishing the catalog: re-run it and the links rebuild.
#
# A phrase matches when all of its meaningful words appear in the title, not when the
# phrase appears verbatim — guideline titles insert words into the middle of a concept
# ("cuidados multidisciplinarios en el embarazo" is about prenatal care) and a literal
# match misses every one of them. Words are compared accent-stripped and roughly
# singularised, because the catalog writes "dislipidemias" where the taxonomy says
# "dislipidemia".
#
# Only the title is read. The body of a guideline mentions dozens of conditions it is not
# about, and matching on it turns every guideline into every topic.
module Gpc
  class TopicLinker < ApplicationService
    # Spanish function words. They carry no topic and would otherwise let a phrase made
    # mostly of them match anything.
    STOPWORDS = %w[
      a al ante bajo con contra de del e el en entre la las lo los mas o para por
      se segun sin so sobre su sus tras un una unas unos y
    ].to_set.freeze

    # Spanish turns nouns into adjectives freely, and the catalog and the taxonomy pick
    # different ones: "Asma en pediatría" against "asma en edad pediátrica", "cirugía"
    # against "quirúrgico". Comparing a fixed-length stem catches those without a
    # dictionary. Seven characters is the shortest length that does not also merge words
    # that mean different things — at six, "cardiopatía" and "cardiología" collide.
    STEM_LENGTH = 7

    # Below this, a match is one short word inside a long title — true, but too thin to
    # build a study day from. Kept rather than dropped so it can still widen a search.
    CONFIDENT_RELEVANCE = 0.2

    def call
      topics = Topic.all.to_a
      return failure("No hay temas: corre primero Taxonomy::Seeder") if topics.empty?

      phrases = topics.to_h { |topic| [topic, topic.search_phrases.map { |phrase| words(phrase) }] }
      counts = Hash.new(0)

      Guideline.find_each do |guideline|
        counts[:links] += link(guideline, phrases)
        counts[:guidelines] += 1
      end

      success(counts.merge(summary))
    end

    private

    def link(guideline, phrases)
      title = words(guideline.title)
      return 0 if title.empty?

      matches = phrases.filter_map do |topic, candidates|
        matched = candidates.find { |phrase| phrase.any? && phrase.subset?(title) }
        next if matched.nil?

        [topic, relevance(matched, title)]
      end

      matches.each do |topic, relevance|
        GuidelineTopic.find_or_initialize_by(guideline: guideline, topic: topic).update!(relevance: relevance)
      end

      matches.size
    end

    # How much of the title the topic accounts for. A guideline whose title is almost
    # exactly the topic name is squarely about it; one that mentions it in passing is not.
    # Measured on stems, every word would weigh the same. The proportion that matters is
    # how much of the title the topic accounts for, so it is counted in matched stems
    # against total stems.
    def relevance(phrase, title)
      [phrase.size.to_f / title.size, 1.0].min.round(4)
    end

    def words(text)
      I18n.transliterate(text.to_s)
          .downcase
          .scan(/[[:alnum:]]+/)
          .reject { |word| STOPWORDS.include?(word) }
          .map { |word| stem(word) }
          .to_set
    end

    def stem(word)
      singularize(word)[0, STEM_LENGTH]
    end

    # Spanish plurals well enough for matching a title: "dislipidemias" and
    # "quemaduras" must reach topics written in the singular. Words this short are
    # acronyms (IAM, TEP, VIH) and are left alone.
    def singularize(word)
      return word if word.length <= 4
      return word.delete_suffix("es") if word.end_with?("es")

      word.delete_suffix("s")
    end

    def summary
      { linked_guidelines: Guideline.where(id: GuidelineTopic.select(:guideline_id)).count,
        linked_topics: Topic.linked.count,
        confident_links: GuidelineTopic.confident.count }
    end
  end
end

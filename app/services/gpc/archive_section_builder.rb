# Turns an archived guideline's stored text into sections and recommendations shaped
# like the live site's, so that everything downstream — generation, citations, the
# question export — reads both sources the same way.
#
# One section per numbered heading and kind: a PDF's table interleaves evidence and
# recommendations under "4.2.1.1 Diagnóstico clínico", and the live site would have
# filed them as that question's EVIDENCIAS and RECOMENDACIONES.
#
# Sections are keyed by their heading, not by their order, so a parser change that
# adds a row in chapter 4.1 leaves every question citing chapter 4.3 still pointing at
# its recommendation. A section whose statements did not change is not touched at all.
module Gpc
  class ArchiveSectionBuilder < ApplicationService
    # Spanish because they are the source's own words: kind is read back from them by
    # GuidelineSection.kind_from_heading, exactly as for a live section.
    HEADINGS = {
      "evidence" => "EVIDENCIAS",
      "recommendation" => "RECOMENDACIONES",
      "good_practice" => "PUNTOS DE BUENA PRÁCTICA"
    }.freeze

    RECOMMENDATION_ATTRIBUTES = %i[text label grade scale citation].freeze

    def initialize(document)
      super()
      @document = document
    end

    def call
      counts = { sections: 0, rebuilt: 0, recommendations: 0 }

      ActiveRecord::Base.transaction do
        kept = groups.each_with_index.map do |(key, statements), index|
          build(key, statements, index + 2, counts)
        end
        document.derived_sections.where.not(id: kept).destroy_all
      end

      success(counts)
    rescue ActiveRecord::InvalidForeignKey
      failure("#{catalog_key}: hay preguntas que citan recomendaciones que el parser ya no produce")
    end

    def context_for_logging
      { catalog_key: catalog_key }
    end

    private

    attr_reader :document

    def catalog_key
      document.guideline.catalog_key
    end

    # In order of first appearance, keyed by heading and kind. Two headings that differ
    # only in case or accents would share a key, so the second gets a suffix.
    def groups
      grouped = ArchiveRecommendationParser.call(document.body).payload.group_by { |s| [s[:heading], s[:kind]] }
      seen = Hash.new(0)

      grouped.to_h do |(heading, kind), statements|
        base = [(heading || "general").parameterize.first(80), kind].join("-")
        seen[base] += 1
        key = seen[base] > 1 ? "#{base}-#{seen[base]}" : base
        [key, statements]
      end
    end

    def build(key, statements, position, counts)
      section = document.derived_sections.find_or_initialize_by(
        guideline: document.guideline, external_id: "#{document.external_id}/#{key}"
      )
      digest = Digest::SHA256.hexdigest(statements.map { |s| s.slice(*RECOMMENDATION_ATTRIBUTES) }.to_json)
      counts[:sections] += 1
      counts[:recommendations] += statements.size

      if section.content_hash == digest
        section.update!(position: position)
      else
        rebuild(section, statements, position, digest)
        counts[:rebuilt] += 1
      end
      section.id
    end

    def rebuild(section, statements, position, digest)
      first = statements.first
      section.update!(
        heading: HEADINGS.fetch(first[:kind]), kind: first[:kind], position: position,
        chapter: first[:chapter], question_label: (first[:heading] if first[:heading] != first[:chapter]),
        body: statements.pluck(:text).join("\n\n"), content_hash: digest
      )
      section.recommendations.destroy_all
      statements.each.with_index(1) do |statement, index|
        section.recommendations.create!(statement.slice(*RECOMMENDATION_ATTRIBUTES).merge(position: index))
      end
    end
  end
end

# Re-reads every stored section through the current parsers, without touching the site.
#
# Parsers improve; the text they read does not change. Storing sections whole is what
# lets a parser fix reach the entire corpus in one command instead of a re-download.
#
# Questions cite recommendations, so a rebuild must never delete one a question points
# at. A live section that parses the same is left alone, and one that changed under a
# cited statement is reported and skipped rather than taking the question down with it.
module Gpc
  class Reparser < ApplicationService
    def call
      before = Recommendation.count
      conflicts = []

      reparse_live_sections(conflicts)
      clear_ungraded_sections
      archived = rebuild_archive(conflicts)

      success(
        sections: GuidelineSection.graded.original.count, before: before,
        after: Recommendation.count, conflicts: conflicts, **archived
      )
    end

    private

    def reparse_live_sections(conflicts)
      GuidelineSection.graded.original.includes(:guideline, :recommendations).find_each do |section|
        parsed = RecommendationParser.call(section.body).payload
        next if parsed == stored(section, parsed)

        rebuild(section, parsed)
      rescue ActiveRecord::InvalidForeignKey
        conflicts << "#{section.guideline.catalog_key} #{section.external_id}: " \
                     "hay preguntas que citan lo que el parser ya no produce"
      end
    end

    def stored(section, parsed)
      keys = parsed.first.to_h.keys
      section.recommendations.map { |recommendation| recommendation.slice(*keys).symbolize_keys }
    end

    def rebuild(section, parsed)
      ActiveRecord::Base.transaction do
        section.recommendations.destroy_all
        parsed.each { |attributes| section.recommendations.create!(attributes) }
      end
    end

    # A section that stopped being graded — the parser learned it is an anexo, say —
    # keeps no statements.
    def clear_ungraded_sections
      ungraded = GuidelineSection.original.where.not(kind: GuidelineSection::GRADED_KINDS)
      Recommendation.joins(:guideline_section).merge(ungraded).destroy_all
    end

    def rebuild_archive(conflicts)
      counts = { archived_guidelines: 0, archived_recommendations: 0 }

      GuidelineSection.kind_archived_document.includes(:guideline).find_each do |document|
        result = ArchiveSectionBuilder.call(document)
        next conflicts << result.errors.full_messages.to_sentence if result.failure?

        counts[:archived_guidelines] += 1 if result.payload[:recommendations].positive?
        counts[:archived_recommendations] += result.payload[:recommendations]
      end

      counts
    end
  end
end

# Upserts one guideline's fetched sections, and the graded statements inside them.
#
# Idempotent on (guideline, external_id) and keyed on the section's content_hash, the
# same bargain CatalogImporter makes: a re-run rewrites only what the site changed.
# Recommendations are derived entirely from the section body, so when a body does
# change they are rebuilt rather than reconciled — there is no identity to match on,
# and a half-updated set of citations is worse than a rebuilt one.
module Gpc
  class GuidelineImporter < ApplicationService
    def initialize(guideline, sections)
      super()
      @guideline = guideline
      @sections = sections
    end

    def call
      counts = { created: 0, updated: 0, unchanged: 0, recommendations: 0 }

      ActiveRecord::Base.transaction do
        @sections.each { |attributes| import_section(attributes, counts) }
      end

      success(counts)
    rescue ActiveRecord::RecordInvalid => e
      failure("No se pudo guardar la sección: #{e.record.errors.full_messages.to_sentence}")
    end

    def context_for_logging
      { catalog_key: guideline.catalog_key }
    end

    private

    attr_reader :guideline

    def import_section(attributes, counts)
      section = guideline.guideline_sections.find_by(external_id: attributes[:external_id])

      if section.nil?
        section = guideline.guideline_sections.create!(attributes)
        counts[:created] += 1
      elsif section.content_hash == attributes[:content_hash]
        counts[:unchanged] += 1
        counts[:recommendations] += section.recommendations.size
        return
      else
        section.update!(attributes)
        section.recommendations.destroy_all
        counts[:updated] += 1
      end

      counts[:recommendations] += build_recommendations(section) if section.graded?
    end

    def build_recommendations(section)
      parsed = RecommendationParser.call(section.body)
      parsed.payload.each { |attributes| section.recommendations.create!(attributes) }
      parsed.payload.size
    end
  end
end

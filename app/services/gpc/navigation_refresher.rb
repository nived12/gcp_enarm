# Re-reads where each section sits in a guideline's menu, without re-fetching any bodies.
#
# The importer skips a section whose content_hash is unchanged, which is right for text
# and wrong for this: the menu path is metadata about the guideline's navigation, not
# about the section's content, so it can be missing from rows whose bodies are perfectly
# current. This reads one page per guideline instead of the ~3,100 a full re-ingest costs.
module Gpc
  class NavigationRefresher < ApplicationService
    def initialize(scope = Guideline.source_live_site, interval: LiveSiteFetcher::REQUEST_INTERVAL_SECONDS)
      super()
      @scope = scope
      @interval = interval
    end

    def call
      counts = Hash.new(0)

      scope.find_each do |guideline|
        sleep(interval) if interval.positive?
        refresh(guideline, counts)
      end

      success(counts)
    end

    private

    attr_reader :scope, :interval

    def refresh(guideline, counts)
      entries = LiveGuidelineFetcher.new(guideline).section_index
      if entries.blank?
        counts[:skipped] += 1
        return
      end

      entries.each do |entry|
        section = guideline.guideline_sections.find_by(external_id: entry[:external_id])
        next if section.nil?

        section.update!(chapter: entry[:chapter], question_label: entry[:question_label])
        counts[:updated] += 1
      end
      counts[:guidelines] += 1
    end
  end
end

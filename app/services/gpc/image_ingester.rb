# Builds the figure library from sections this app has already stored.
#
# The metadata comes from stored HTML, so re-running after a parser change costs nothing
# and touches no network. Only the bytes are fetched, and only once: a figure whose file
# is already attached and whose path has not moved is left alone, which is what makes
# this safe to run again after it fails halfway.
module Gpc
  class ImageIngester < ApplicationService
    def initialize(scope = GuidelineSection.all, interval: LiveSiteFetcher::REQUEST_INTERVAL_SECONDS,
                   download: true)
      super()
      @scope = scope
      @interval = interval
      @download = download
    end

    def call
      counts = Hash.new(0)

      candidates.find_each { |section| ingest(section, counts) }

      success(counts)
    end

    private

    attr_reader :scope, :interval, :download

    # Sections that publish an image, plus any that used to. A section whose figure was
    # withdrawn upstream, or that the filter no longer accepts, has no <img> left to find
    # it by — and it still has rows here that have to go.
    def candidates
      publishing = GuidelineSection.where(id: scope.where("body LIKE ?", "%<img%").select(:id))
      stale = GuidelineSection.where(
        id: ClinicalImage.where(guideline_section_id: scope.select(:id)).select(:guideline_section_id)
      )
      publishing.or(stale).includes(:guideline)
    end

    def ingest(section, counts)
      rows = ImageParser.call(section).payload

      rows.each do |attributes|
        image = section.clinical_images.find_or_initialize_by(position: attributes[:position])
        counts[image.new_record? ? :created : :updated] += 1
        image.update!(attributes.merge(attribution: attribution_for(section.guideline)))
        attach(image, counts)
      end

      prune(section, rows, counts)
    end

    # The filter is expected to change — it is what separates medicine from the
    # guideline's working papers, and it has already been wrong twice. So a re-run has to
    # take rows away as well as add them, or a figure that should never have been kept
    # stays kept forever. A case pointing at one loses its figure, which is the point.
    def prune(section, rows, counts)
      stale = section.clinical_images.where.not(position: rows.map { |row| row[:position] })
      return if stale.empty?

      counts[:removed] += stale.count
      stale.destroy_all
    end

    def attach(image, counts)
      return unless download
      return counts[:already_stored] += 1 if image.file.attached?

      sleep(interval) if interval.positive?
      result = ImageFetcher.call(image.remote_path)
      return counts[:failed] += 1 unless result.success?

      payload = result.payload
      image.file.attach(
        io: StringIO.new(payload[:bytes]), filename: payload[:filename],
        content_type: payload[:content_type]
      )
      counts[:downloaded] += 1
    end

    # The licence asks for the source to travel with the figure, so it is written once
    # here rather than assembled by whichever view happens to render it.
    def attribution_for(guideline)
      ["GPC #{guideline.catalog_key}", guideline.title, guideline.year].compact_blank.join(" · ")
    end
  end
end

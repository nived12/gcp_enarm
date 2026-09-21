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

    def candidates
      scope.where("body LIKE ?", "%<img%").includes(:guideline)
    end

    def ingest(section, counts)
      ImageParser.call(section).payload.each do |attributes|
        image = section.clinical_images.find_or_initialize_by(position: attributes[:position])
        counts[image.new_record? ? :created : :updated] += 1
        image.update!(attributes.merge(attribution: attribution_for(section.guideline)))
        attach(image, counts)
      end
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

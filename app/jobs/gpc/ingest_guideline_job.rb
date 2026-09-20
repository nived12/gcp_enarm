# Fetches one guideline's sections from the live site and imports them.
#
# One guideline per job, on its own queue: a full catalog run is ~3,100 requests to a
# single government server, and queueing them one guideline at a time keeps that load
# serial and restartable. A failed guideline does not cost the other 52.
module Gpc
  class IngestGuidelineJob < ApplicationJob
    queue_as :ingestion

    def perform(guideline)
      fetched = LiveGuidelineFetcher.call(guideline)
      return unless fetched.success?

      GuidelineImporter.call(guideline, fetched.payload)
    end
  end
end

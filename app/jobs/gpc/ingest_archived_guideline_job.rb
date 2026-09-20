# Downloads and imports one archived guideline summary.
#
# On the same single-thread queue as the live-site jobs: different server, same
# courtesy, and it keeps the whole ingestion serial and restartable.
module Gpc
  class IngestArchivedGuidelineJob < ApplicationJob
    queue_as :ingestion

    def perform(entry)
      ArchiveGuidelineImporter.call(entry)
    end
  end
end

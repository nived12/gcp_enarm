# Downloads and imports one archived guideline summary.
#
# On the same single-thread queue as the live-site jobs: different server, same
# courtesy, and it keeps the whole ingestion serial and restartable.
module Gpc
  class IngestArchivedGuidelineJob < ApplicationJob
    queue_as :ingestion

    # The archive throttles, resets connections and truncates downloads. None of that is
    # a reason to lose a guideline, and none of it is fixed by trying again immediately.
    retry_on StandardError, wait: :polynomially_longer, attempts: 5

    def perform(entry)
      ArchiveGuidelineImporter.call(entry)
    end
  end
end

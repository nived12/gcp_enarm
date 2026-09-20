# Re-reads the live catalog and re-ingests every guideline on it.
#
# Scheduled quarterly in config/recurring.yml. It costs nothing to run — Solid Queue
# lives inside the Puma process, so there is no worker to pay for — and it is the only
# thing keeping the corpus honest: the catalog is not frozen (SS-757-25 appeared after
# our first survey), guidelines get republished with new recommendations, and a
# guideline that ages out of its five-year window changes what a student should be told
# about it.
#
# It re-reads every guideline rather than only the ones whose catalog entry changed. The
# catalog row carries the title, year and specialties; it says nothing about the
# recommendations inside, so a silent content update would otherwise go unnoticed. That
# is ~3,100 requests once a quarter, paced at one thread — nothing for us, and little
# enough for a small government server.
#
# The web archive is deliberately not refreshed: those captures are history and will not
# change. New captures of long-dead pages are rare enough to be worth a manual
# gpc:archive when someone wonders.
module Gpc
  class RefreshCatalogJob < ApplicationJob
    queue_as :ingestion

    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform
      fetched = LiveCatalogFetcher.call
      return Rails.logger.warn("Refresh: #{fetched.errors.full_messages.to_sentence}") unless fetched.success?

      imported = CatalogImporter.call(fetched.payload)
      return Rails.logger.warn("Refresh: #{imported.errors.full_messages.to_sentence}") unless imported.success?

      Rails.logger.info("Refresh del catálogo: #{imported.payload.inspect}")
      Guideline.source_live_site.find_each { |guideline| IngestGuidelineJob.perform_later(guideline) }
    end
  end
end

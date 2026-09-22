# Turns one archived-catalog entry into a Guideline and its text.
#
# The title only exists inside the PDF, so unlike the live-site path there is no
# catalog step that can run on its own: fetching and importing are the same act.
module Gpc
  class ArchiveGuidelineImporter < ApplicationService
    SUMMARY_HEADING = "RESUMEN DE EVIDENCIAS Y RECOMENDACIONES".freeze

    def initialize(entry)
      super()
      @entry = entry.symbolize_keys
    end

    def call
      return success(skipped: :published_live) if published_live?
      return success(skipped: :already_imported) if already_imported?

      document = fetch_document
      return failure if has_errors?

      guideline = upsert_guideline(document)
      built = ArchiveSectionBuilder.call(upsert_section(guideline, document))
      return failure(built.errors.full_messages.to_sentence) if built.failure?

      success(
        catalog_key: entry[:catalog_key], title: guideline.title, pages: document[:page_count],
        recommendations: built.payload[:recommendations]
      )
    rescue ActiveRecord::RecordInvalid => e
      failure("No se pudo guardar #{entry[:catalog_key]}: #{e.record.errors.full_messages.to_sentence}")
    end

    def context_for_logging
      { catalog_key: entry[:catalog_key] }
    end

    private

    attr_reader :entry

    # The live site is the newer copy of anything it still publishes, so an archived
    # capture of the same key is history and must not overwrite it.
    def published_live?
      Guideline.source_live_site.exists?(catalog_key: entry[:catalog_key])
    end

    # external_id is the capture timestamp, so the same one means the same bytes. Re-running
    # is then free rather than another ~1 MB download, which is what makes a run that the
    # archive interrupted restartable instead of restarted.
    def already_imported?
      GuidelineSection.kind_archived_document.joins(:guideline)
                      .where(guidelines: { catalog_key: entry[:catalog_key] }, external_id: entry[:external_id])
                      .exists?
    end

    def fetch_document
      bytes = ArchivePdfFetcher.call(entry[:document_url])
      return add_errors_from(bytes) unless bytes.success?

      extracted = PdfExtractor.call(bytes.payload)
      return add_errors_from(extracted) unless extracted.success?

      extracted.payload
    end

    def upsert_guideline(document)
      # A PDF whose running header did not extract still has its catalog key, which is
      # how a student cites it anyway.
      title = ArchiveTitles.for(entry[:catalog_key]) || document[:title].presence || entry[:catalog_key]
      attributes = entry.merge(title: title, content_hash: Digest::SHA256.hexdigest(document[:text]))

      guideline = Guideline.find_or_initialize_by(catalog_key: entry[:catalog_key])
      guideline.assign_attributes(attributes.merge(ingested_at: Time.current))
      guideline.save!
      guideline
    end

    def upsert_section(guideline, document)
      section = guideline.guideline_sections.find_or_initialize_by(external_id: entry[:external_id])
      section.assign_attributes(
        heading: SUMMARY_HEADING, kind: "archived_document", position: 1,
        body: document[:text], content_hash: Digest::SHA256.hexdigest(document[:text])
      )
      section.save!
      section
    end
  end
end

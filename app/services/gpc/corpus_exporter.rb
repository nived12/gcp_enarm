# Writes the scraped corpus to one portable file.
#
# Only guidelines and their sections are exported, because they are the only part that
# is expensive to obtain: ~3,800 requests to a small government server plus ~700 PDFs
# from a rate-limited archive, over a couple of hours. Everything downstream —
# recommendations, the taxonomy, the guideline/topic links — is derived from these by
# code that runs in seconds, so it is rebuilt on the far side instead of shipped.
#
# That is not only smaller. It means the recommendations in an environment always match
# that environment's parser, rather than being frozen at whatever the parser said on the
# day the file was written.
module Gpc
  class CorpusExporter < ApplicationService
    GUIDELINE_ATTRIBUTES = %w[
      catalog_key title institution year source external_id
      catalog_url document_url levels_of_care specialty_labels content_hash ingested_at
    ].freeze

    SECTION_ATTRIBUTES = %w[
      external_id heading clinical_question kind position body content_hash
    ].freeze

    BATCH_SIZE = 50

    def initialize(path)
      super()
      @path = path
    end

    def call
      guidelines = 0
      sections = 0

      FileUtils.mkdir_p(File.dirname(path))
      Zlib::GzipWriter.open(path) do |file|
        Guideline.order(:catalog_key).find_each(batch_size: BATCH_SIZE) do |guideline|
          file.puts(line("guideline", guideline.slice(*GUIDELINE_ATTRIBUTES)))
          guidelines += 1
          sections += write_sections(file, guideline)
        end
      end

      success(path: path, guidelines: guidelines, sections: sections, bytes: File.size(path))
    end

    private

    attr_reader :path

    def write_sections(file, guideline)
      guideline.guideline_sections.order(:position).find_each(batch_size: BATCH_SIZE) do |section|
        # Sections point at their guideline by catalog_key, never by id: the two
        # databases number their rows independently and only the key is meaningful.
        attributes = section.slice(*SECTION_ATTRIBUTES).merge("catalog_key" => guideline.catalog_key)
        file.puts(line("section", attributes))
      end

      guideline.guideline_sections.size
    end

    def line(record, attributes)
      attributes.merge("record" => record).to_json
    end
  end
end

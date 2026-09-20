# Lists every guideline summary the Wayback Machine holds for cenetec-difusion.com.
#
# This is the only route to the ~770 guidelines the live site dropped, Cirugía General
# among them — a troncal worth roughly a fifth of the exam and absent from gpc.salud.gob.mx
# entirely. One CDX query returns the whole index; no crawling.
#
# Returns attribute hashes without a title: the title is inside the PDF, so it is
# Gpc::ArchiveGuidelineImporter that completes the row.
module Gpc
  class ArchiveCatalogFetcher < WebArchiveFetcher
    CDX_URL = "#{BASE_URL}/cdx/search/cdx".freeze
    CDX_TARGET = "cenetec-difusion.com/CMGPC*".freeze

    # ER.pdf is the "Resumen de Evidencias y Recomendaciones" — the graded statements
    # on their own. RR.pdf is the full reference guide and is mostly prose we do not
    # generate from.
    SUMMARY_FILENAME = "ER.pdf".freeze

    # Higher than the ~1,400 rows the archive holds, so one query is always enough.
    ROW_LIMIT = 20_000

    # Keys the site published as "GPC-IMSS-028-22" and as "IMSS-028-22" are the same
    # guideline; the prefix is decoration. A handful of captures have keys that fit
    # neither shape ("DIF-25709") and are skipped rather than guessed at.
    KEY_PATTERN = %r{/CMGPC/(?:GPC-)?([A-Z]+-\d{3,4}-\d{2})/#{SUMMARY_FILENAME}\z}i

    def call
      body = get(CDX_URL, "El índice del archivo", cdx_query)
      return failure if has_errors?

      entries = parse(body)
      return failure("El índice del archivo no devolvió ninguna guía") if entries.empty?

      success(entries)
    end

    private

    def cdx_query
      { url: CDX_TARGET, output: "json", fl: "original,timestamp,statuscode,mimetype",
        collapse: "urlkey", limit: ROW_LIMIT }
    end

    # CDX answers with a JSON array of arrays whose first row is the column names.
    def parse(body)
      rows = ActiveSupport::JSON.decode(body)
      return [] if rows.blank?

      rows.drop(1).filter_map { |row| entry_from(*row) }.uniq { |entry| entry[:catalog_key] }
    rescue JSON::ParserError
      failure("El índice del archivo no devolvió JSON")
      []
    end

    def entry_from(original, timestamp, status_code, mime_type)
      return unless status_code == "200"

      # A capture can answer 200 with the archive's own error page. The recorded MIME
      # type is what says whether the bytes are really a PDF.
      return unless mime_type == "application/pdf"

      catalog_key = original[KEY_PATTERN, 1]&.upcase
      return if catalog_key.nil?

      {
        catalog_key: catalog_key,
        institution: Guideline.institution_from_catalog_key(catalog_key),
        year: year_from(catalog_key),
        source: "web_archive",
        external_id: timestamp,
        catalog_url: "#{BASE_URL}/web/#{timestamp}/#{original}",
        document_url: raw_bytes_url(timestamp, original)
      }
    end

    # Without the "id_" suffix the archive rewrites what it serves and injects its own
    # toolbar, which corrupts a PDF. This form returns the bytes as captured.
    def raw_bytes_url(timestamp, original)
      "#{BASE_URL}/web/#{timestamp}id_/#{original}"
    end

    # The last pair of a catalog key is the year it was published: IMSS-028-22 is 2022.
    # CENETEC started in 2008, so a two-digit year is unambiguous for another 80 years.
    def year_from(catalog_key)
      2000 + catalog_key.split("-").last.to_i
    end
  end
end

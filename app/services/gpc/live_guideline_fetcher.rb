# Reads one guideline's full contents off the live site.
#
# The contents page is an accordion whose leaves each carry a data-id; the body of a
# leaf is fetched separately from ObtenerContenidoSeccion. That is 30–152 requests per
# guideline, so the whole run is deliberately paced — see LiveSiteFetcher.
#
# Returns an array of section attribute hashes; Gpc::GuidelineImporter persists them.
module Gpc
  class LiveGuidelineFetcher < LiveSiteFetcher
    GUIDELINE_PATH = "/DDIMBE/DDIMBE/ContenidoGuia".freeze
    SECTION_PATH = "/DDIMBE/DDIMBE/ObtenerContenidoSeccion".freeze

    def initialize(guideline, interval: REQUEST_INTERVAL_SECONDS)
      super()
      @guideline = guideline
      @interval = interval
    end

    def call
      return failure("La guía #{guideline.catalog_key} no tiene DocumentoID") if guideline.external_id.blank?

      contents = get(GUIDELINE_PATH, "La guía", DocumentoID: guideline.external_id)
      return failure if has_errors?

      entries = section_entries(contents)
      return failure("La guía #{guideline.catalog_key} no listó ninguna sección") if entries.empty?

      sections = entries.filter_map { |entry| fetch_section(entry) }
      return failure if has_errors?

      success(sections)
    end

    def context_for_logging
      { catalog_key: guideline.catalog_key, external_id: guideline.external_id }
    end

    private

    attr_reader :guideline, :interval

    def section_entries(contents)
      links = Nokogiri::HTML(contents).css("a.link-cargar-seccion[data-id]")

      links.filter_map.with_index(1) do |link, position|
        heading = link.text.squish
        next if heading.blank?

        { external_id: link["data-id"], heading: heading, position: position }
      end
    end

    def fetch_section(entry)
      sleep(interval) if interval.positive?
      body = get(SECTION_PATH, "La sección #{entry[:external_id]}", id: entry[:external_id])
      return if body.nil?

      # An id the site does not know returns the whole application shell with a 200
      # rather than a 404, so the fragment has to be recognised rather than trusted.
      return failure("La sección #{entry[:external_id]} no devolvió contenido") if full_page?(body)

      entry.merge(
        kind: GuidelineSection.kind_from_heading(entry[:heading]),
        clinical_question: clinical_question(body, entry[:heading]),
        body: body,
        content_hash: Digest::SHA256.hexdigest(body)
      )
    end

    def full_page?(body)
      body.include?("<!DOCTYPE")
    end

    # A section's <h2> reads "<the PICO question><br><br>RECOMENDACIONES". Only the
    # question is worth keeping, and only when the tail really is this section's own
    # heading repeated — on OBJETIVOS and the anexos the <h2> is just the heading.
    def clinical_question(body, heading)
      h2 = Nokogiri::HTML.fragment(body).at_css("h2")
      return if h2.nil?

      segments = h2.inner_html.split(%r{<br\s*/?>}i).map { |part| Nokogiri::HTML.fragment(part).text.squish }
      segments = segments.compact_blank
      segments.pop if segments.size > 1 && segments.last.casecmp?(heading)

      segments.join(" ").presence if segments.size.positive? && !segments.join(" ").casecmp?(heading)
    end
  end
end

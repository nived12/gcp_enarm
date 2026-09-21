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

    # The contents menu on its own, without fetching a single section body. Used to
    # backfill the menu path onto sections whose text is already current.
    def section_index
      return [] if guideline.external_id.blank?

      contents = get(GUIDELINE_PATH, "La guía", DocumentoID: guideline.external_id)
      return [] if contents.nil?

      section_entries(contents)
    end

    attr_reader :guideline, :interval

    private

    # The contents menu is a two-level accordion: a chapter ("FACTORES DE RIESGO"), then
    # the clinical question the site numbers itself ("PREGUNTA 1"), then the leaves. None
    # of those levels is addressable, so the only way to point a reader at a
    # recommendation is to repeat the path they have to click.
    #
    # Walked from each leaf outwards rather than from the chapters down, because a chapter
    # can hold loose sections *and* numbered questions at once — ANEXOS carries GLOSARIO DE
    # TERMINOS beside three of them — and descending from the chapters silently dropped the
    # loose ones.
    def section_entries(contents)
      links = Nokogiri::HTML(contents).css("a.link-cargar-seccion[data-id]")

      links.filter_map.with_index(1) do |link, position|
        heading = link.text.squish
        next if heading.blank?

        { external_id: link["data-id"], heading: heading, position: position,
          chapter: chapter_for(link), question_label: question_label_for(link) }
      end
    end

    # Nokogiri lists ancestors nearest first, so the outermost accordion item is the
    # chapter and the innermost is the numbered question — when there is one.
    def chapter_for(link)
      header_of(link.ancestors(".accordion-item").last)
    end

    def question_label_for(link)
      items = link.ancestors(".accordion-item")
      return if items.size < 2

      header_of(items.first)
    end

    # Both guards are for markup drift, not for the page as it stands: this site is
    # undocumented and has already moved once, and a leaf that ends up outside the
    # accordion should cost a missing menu path, not a NoMethodError that kills the run.
    # `text` is not guarded — Nokogiri always returns a String for it.
    def header_of(item)
      button = item&.at_css("> .accordion-header button")
      button&.text&.squish
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

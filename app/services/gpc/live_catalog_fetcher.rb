# Reads the whole published catalog off the live Secretaría de Salud site.
#
# The site exposes a FiltrarGuias POST endpoint, but as of 2026-09 it returns 500
# for the documented payload and it is not needed: GET /DDIMBE is server-rendered
# with every card, so one plain request gets the entire catalog. No antiforgery
# token, no undocumented JSON contract.
#
# Returns an array of attribute hashes; persisting them is Gpc::CatalogImporter's
# job. Keeping the parse pure is what lets it be tested against a saved page.
module Gpc
  class LiveCatalogFetcher < ApplicationService
    BASE_URL = "https://gpc.salud.gob.mx".freeze
    CATALOG_PATH = "/DDIMBE".freeze
    GUIDELINE_PATH = "/DDIMBE/DDIMBE/ContenidoGuia".freeze

    # The card labels are Spanish because the source document is Spanish. They are
    # data we match against, not names we chose.
    LABELS = {
      catalog_key: "Clave de Catálogo Maestro",
      specialties: "Especialidad médica",
      levels_of_care: "Nivel de Atención",
      year: "Año de publicación"
    }.freeze

    # A small government server with no CDN. One request per run is already polite;
    # the timeout is generous because it is frequently slow rather than down.
    TIMEOUT_SECONDS = 30

    def call
      body = fetch_catalog_page
      return failure if has_errors?

      entries = parse(body)
      return failure("El catálogo no devolvió ninguna guía") if entries.empty?

      success(entries)
    end

    private

    def fetch_catalog_page
      response = HTTParty.get(
        "#{BASE_URL}#{CATALOG_PATH}", timeout: TIMEOUT_SECONDS,
        headers: { "User-Agent" => user_agent }
      )
      return response.body if response.success?

      failure("El catálogo respondió #{response.code}")
      nil
    rescue HTTParty::Error, SocketError, Timeout::Error, Errno::ECONNREFUSED => e
      failure("No se pudo leer el catálogo: #{e.message}")
      nil
    end

    def parse(body)
      Nokogiri::HTML(body).css("#ListaGuias .card").filter_map { |card| entry_from(card) }
    end

    def entry_from(card)
      catalog_key = field(card, :catalog_key)
      link = card.at_css("h3.card-title a")
      return if catalog_key.blank? || link.nil?

      external_id = Rack::Utils.parse_query(URI(link["href"]).query)["DocumentoID"]

      {
        catalog_key: catalog_key,
        title: link.text.squish,
        institution: Guideline.institution_from_catalog_key(catalog_key),
        year: field(card, :year).presence&.to_i,
        source: "live_site",
        external_id: external_id,
        catalog_url: "#{BASE_URL}#{CATALOG_PATH}",
        document_url: "#{BASE_URL}#{GUIDELINE_PATH}?DocumentoID=#{external_id}",
        specialty_labels: split_list(field(card, :specialties)),
        levels_of_care: split_list(field(card, :levels_of_care)).filter_map { |l| l[/\d+/]&.to_i }
      }
    end

    # Each field is a <strong> label followed by a bare text node. Reading the
    # sibling rather than the parent's text keeps the inline <svg> icons out.
    def field(card, name)
      label = LABELS.fetch(name)
      node = card.css("strong").find { |strong| strong.text.squish.start_with?(label) }
      node&.next_sibling&.text.to_s.squish
    end

    def split_list(value)
      value.to_s.split(",").map(&:strip).reject(&:blank?)
    end

    def user_agent
      ENV.fetch("GPC_USER_AGENT", "GPCEnarm/1.0 (+https://gpcenarm.mx; contacto@gpcenarm.mx)")
    end
  end
end

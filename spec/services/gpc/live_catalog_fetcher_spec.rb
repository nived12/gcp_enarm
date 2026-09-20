require "rails_helper"

RSpec.describe Gpc::LiveCatalogFetcher do
  # A slice of the real page, markup untouched: three cards covering all three
  # institution prefixes the catalog currently publishes.
  let(:catalog_html) { file_fixture("gpc/live_catalog.html").read }
  let(:catalog_url) { "https://gpc.salud.gob.mx/DDIMBE" }

  def stub_catalog(status: 200, body: catalog_html)
    stub_request(:get, catalog_url).to_return(status: status, body: body)
  end

  describe "a successful fetch" do
    before { stub_catalog }

    it "returns one entry per card" do
      response = described_class.call

      expect(response).to be_success
      expect(response.payload.size).to eq(3)
    end

    it "parses every field off a card" do
      entry = described_class.call.payload.find { |e| e[:catalog_key] == "IMSS-028-22" }

      expect(entry).to include(
        catalog_key: "IMSS-028-22",
        title: "Atención y cuidados multidisciplinarios en el embarazo",
        institution: "imss",
        year: 2022,
        source: "live_site",
        external_id: "3079",
        specialty_labels: ["Gineco-Obstetricia"],
        levels_of_care: [1, 2]
      )
    end

    it "builds the per-guideline document URL from the site's own DocumentoID" do
      entry = described_class.call.payload.first

      expect(entry[:document_url])
        .to eq("https://gpc.salud.gob.mx/DDIMBE/DDIMBE/ContenidoGuia?DocumentoID=#{entry[:external_id]}")
    end

    it "derives the institution from the catalog key prefix" do
      institutions = described_class.call.payload.map { |e| e[:institution] }

      expect(institutions).to contain_exactly("imss", "health_ministry", "dif")
    end

    it "splits multi-valued specialty and level fields" do
      entry = described_class.call.payload.find { |e| e[:levels_of_care].size > 2 }

      expect(entry[:levels_of_care]).to eq([1, 2, 3])
    end

    it "keeps the icon markup out of the parsed values" do
      titles_and_keys = described_class.call.payload.flat_map { |e| [e[:title], e[:catalog_key]] }

      expect(titles_and_keys).to all(satisfy { |v| !v.include?("svg") && !v.include?("<") })
    end

    it "identifies itself so the operators can see who is reading them" do
      described_class.call

      expect(
        a_request(:get, catalog_url)
                .with(headers: { "User-Agent" => /GPCEnarm/ })
      ).to have_been_made
    end
  end

  describe "when the site is unhappy" do
    it "fails on a non-success response rather than parsing an error page" do
      stub_catalog(status: 500, body: "<html><body>Error</body></html>")

      response = described_class.call

      expect(response).to be_failure
      expect(response.errors.map(&:message)).to include(a_string_matching(/respondió 500/))
    end

    it "fails when the page renders but contains no cards" do
      stub_catalog(body: "<html><body><div id='ListaGuias'></div></body></html>")

      response = described_class.call

      expect(response).to be_failure
      expect(response.errors.map(&:message)).to include(a_string_matching(/ninguna guía/))
    end

    it "fails rather than raising when the connection times out" do
      stub_request(:get, catalog_url).to_timeout

      response = described_class.call

      expect(response).to be_failure
      expect(response.errors.map(&:message)).to include(a_string_matching(/No se pudo leer el catálogo/))
    end

    # The site's markup is undocumented and has already changed once. These two
    # guard the fields most likely to drift, so a format change degrades the entry
    # rather than raising mid-ingestion.
    it "leaves the year nil on the one card missing it, and still parses the rest" do
      stub_catalog(body: catalog_html.sub("Año de publicación", "Publicado"))

      years = described_class.call.payload.map { |e| e[:year] }

      expect(years.first).to be_nil
      expect(years.drop(1)).to all(be_present)
    end

    it "drops a level of care that carries no number" do
      stub_catalog(body: catalog_html.sub("Nivel 1,Nivel 2,Nivel 3", "Todos los niveles"))

      levels = described_class.call.payload.map { |e| e[:levels_of_care] }

      expect(levels).to include([])
    end

    it "skips a card with no catalog key instead of importing a nameless guideline" do
      stub_catalog(body: catalog_html.sub("Clave de Catálogo Maestro", "Otro campo"))

      expect(described_class.call.payload.size).to eq(2)
    end
  end
end

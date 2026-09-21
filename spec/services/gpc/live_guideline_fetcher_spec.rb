require "rails_helper"

RSpec.describe Gpc::LiveGuidelineFetcher do
  # SS-757-25 as the site serves it: the contents page and three of its sections,
  # markup untouched.
  let(:guideline) { create(:guideline, catalog_key: "SS-757-25", institution: "health_ministry", external_id: "4081") }
  let(:contents_url) { "https://gpc.salud.gob.mx/DDIMBE/DDIMBE/ContenidoGuia?DocumentoID=4081" }
  let(:section_url) { %r{https://gpc\.salud\.gob\.mx/DDIMBE/DDIMBE/ObtenerContenidoSeccion} }

  def stub_contents(status: 200, body: file_fixture("gpc/guideline_contents.html").read)
    stub_request(:get, contents_url).to_return(status: status, body: body)
  end

  def stub_sections(body: file_fixture("gpc/section_36777.html").read)
    stub_request(:get, section_url).to_return(status: 200, body: body)
  end

  # The pause between section requests is politeness towards a small government
  # server, not behaviour under test.
  def fetch = described_class.call(guideline, interval: 0)

  describe "a successful fetch" do
    before do
      stub_contents
      stub_sections
    end

    it "returns one entry per section the contents page lists" do
      response = fetch

      expect(response).to be_success
      expect(response.payload.size).to eq(31)
    end

    it "numbers sections in the order the contents page lists them" do
      expect(fetch.payload.map { |s| s[:position] }).to eq((1..31).to_a)
    end

    it "carries the site's own section id, which the content endpoint needs" do
      expect(fetch.payload.first).to include(external_id: "36770", heading: "OBJETIVOS")
    end

    it "requests each section by that id" do
      fetch

      expect(a_request(:get, section_url).with(query: { id: "36770" })).to have_been_made
    end

    it "classifies a section from the heading the site gives it" do
      kinds = fetch.payload.group_by { |s| s[:kind] }.transform_values(&:size)

      expect(kinds).to eq(
        "other" => 11, "evidence" => 8, "recommendation" => 6,
        "key_recommendation" => 5, "good_practice" => 1
      )
    end

    it "records the menu path a reader has to click, since no section has a URL" do
      entry = fetch.payload.find { |s| s[:heading] == "RECOMENDACIONES CLAVE" }

      expect(entry[:chapter]).to be_present
      expect(entry[:question_label]).to match(/PREGUNTA/)
    end

    it "leaves the question blank for a section that sits under no numbered question" do
      entry = fetch.payload.find { |s| s[:heading] == "OBJETIVOS" }

      expect(entry[:question_label]).to be_nil
      expect(entry[:chapter]).to be_present
    end

    it "keeps a loose section in a chapter that also holds numbered questions" do
      # ANEXOS carries GLOSARIO DE TERMINOS beside three numbered questions. Descending
      # from the chapters dropped it; the ancestor walk does not.
      headings = fetch.payload.map { |s| s[:heading] }

      expect(headings).to include("GLOSARIO DE TERMINOS")
    end

    it "survives a menu that has moved out from under the accordion" do
      # The site is undocumented and has drifted before. A leaf with no accordion around
      # it should cost the menu path, not the whole run.
      stub_contents(body: <<~HTML)
        <a class="link-cargar-seccion" data-id="9">RECOMENDACIONES</a>
      HTML

      entry = fetch.payload.first

      expect(entry).to include(external_id: "9", chapter: nil, question_label: nil)
    end

    it "survives a chapter whose header button is gone" do
      stub_contents(body: <<~HTML)
        <div id="accordionRaiz">
          <div class="accordion-item">
            <h4 class="accordion-header"></h4>
            <div class="accordion-body">
              <a class="link-cargar-seccion" data-id="9">RECOMENDACIONES</a>
            </div>
          </div>
        </div>
      HTML

      expect(fetch.payload.first[:chapter]).to be_nil
    end

    it "skips a menu entry with no label" do
      stub_contents(body: <<~HTML)
        <div id="accordionRaiz">
          <div class="accordion-item">
            <h4 class="accordion-header"><button>FACTORES DE RIESGO</button></h4>
            <div class="accordion-body">
              <a class="link-cargar-seccion" data-id="1"> </a>
              <a class="link-cargar-seccion" data-id="2">EVIDENCIAS</a>
            </div>
          </div>
        </div>
      HTML

      expect(fetch.payload.map { |s| s[:external_id] }).to eq(["2"])
    end

    it "pauses between section requests, because the site is one small server" do
      fetcher = described_class.new(guideline)
      allow(fetcher).to receive(:sleep)

      fetcher.call

      expect(fetcher).to have_received(:sleep).with(described_class::REQUEST_INTERVAL_SECONDS).exactly(31).times
    end

    it "names itself in the User-Agent so the site can see who is reading" do
      fetch

      expect(a_request(:get, contents_url).with(headers: { "User-Agent" => /GPCEnarm/ })).to have_been_made
    end
  end

  describe "the clinical question" do
    before { stub_contents }

    it "is lifted from the section's own heading, without the repeated section name" do
      stub_sections

      question = fetch.payload.find { |s| s[:external_id] == "36777" }[:clinical_question]

      expect(question).to eq(
        "EN POBLACIÓN MAYOR DE 18 AÑOS DE EDAD ¿DEBERÍAN DE USARSE MEDIDAS DE PREVENCIÓN DE " \
        "PICADURAS Y EL CONTROL DE VECTORES CONTRA NO EMPLEARLAS PARA EVITAR LA INFECCIÓN POR CHIKV?"
      )
    end

    it "is nil on a section whose heading is only its own name" do
      stub_sections(body: "<h2>OBJETIVOS</h2><hr class=\"red\"><p>Texto.</p>")

      expect(fetch.payload.first[:clinical_question]).to be_nil
    end

    it "is nil on a section with no heading at all" do
      stub_sections(body: "<p>Texto suelto.</p>")

      expect(fetch.payload.first[:clinical_question]).to be_nil
    end
  end

  describe "when the site does not cooperate" do
    it "fails when the guideline has no DocumentoID" do
      guideline.update_column(:external_id, nil)

      expect(fetch).not_to be_success
    end

    it "fails when the contents page errors" do
      stub_contents(status: 500)

      expect(fetch.errors.full_messages.first).to include("500")
    end

    it "fails when the contents page lists no sections" do
      stub_contents(body: "<html><body>Sin contenido</body></html>")

      expect(fetch.errors.full_messages.first).to include("no listó ninguna sección")
    end

    it "fails when a section errors" do
      stub_contents
      stub_request(:get, section_url).to_return(status: 503)

      expect(fetch).not_to be_success
    end

    it "fails when the site answers an unknown id with its own home page" do
      stub_contents
      stub_sections(body: file_fixture("gpc/section_unknown.html").read)

      expect(fetch.errors.full_messages.first).to include("no devolvió contenido")
    end

    it "fails when the site is unreachable" do
      stub_request(:get, contents_url).to_raise(SocketError.new("getaddrinfo failed"))

      expect(fetch.errors.full_messages.first).to include("getaddrinfo failed")
    end
  end
end

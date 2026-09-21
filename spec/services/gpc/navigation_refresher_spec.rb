require "rails_helper"

RSpec.describe Gpc::NavigationRefresher do
  let(:guideline) do
    create(
      :guideline, source: "live_site", catalog_key: "SS-757-25",
      institution: "health_ministry", external_id: "4081"
    )
  end
  let(:contents_url) { "https://gpc.salud.gob.mx/DDIMBE/DDIMBE/ContenidoGuia?DocumentoID=4081" }

  def stub_contents(body: file_fixture("gpc/guideline_contents.html").read, status: 200)
    stub_request(:get, contents_url).to_return(status: status, body: body)
  end

  def refresh = described_class.call(Guideline.where(id: guideline.id), interval: 0)

  it "fills the menu path onto sections that already have their text" do
    section = create(
      :guideline_section, guideline: guideline, external_id: "36770",
      heading: "OBJETIVOS", chapter: nil, question_label: nil
    )
    stub_contents

    result = refresh

    expect(result).to be_success
    expect(section.reload.chapter).to be_present
  end

  it "reads one page per guideline and no section bodies at all" do
    create(:guideline_section, guideline: guideline, external_id: "36770")
    stub_contents

    refresh

    expect(a_request(:get, contents_url)).to have_been_made.once
    expect(a_request(:get, %r{ObtenerContenidoSeccion})).not_to have_been_made
  end

  it "ignores a menu entry we never stored" do
    stub_contents

    expect(refresh.payload[:updated]).to eq(0)
  end

  it "skips a guideline whose contents page will not load, rather than failing the run" do
    create(:guideline_section, guideline: guideline, external_id: "36770")
    stub_contents(status: 500, body: "")

    result = refresh

    expect(result).to be_success
    expect(result.payload[:skipped]).to eq(1)
  end

  it "skips a guideline the site has no id for" do
    guideline.update!(external_id: nil)

    expect(refresh.payload[:skipped]).to eq(1)
  end

  it "pauses between guidelines, because the site is one small server" do
    refresher = described_class.new(Guideline.where(id: guideline.id))
    allow(refresher).to receive(:sleep)
    stub_contents

    refresher.call

    expect(refresher).to have_received(:sleep).with(Gpc::LiveSiteFetcher::REQUEST_INTERVAL_SECONDS).once
  end
end

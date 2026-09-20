require "rails_helper"

RSpec.describe Gpc::Retitler do
  def archived(title:, body:)
    guideline = create(:guideline, source: "web_archive", title: title)
    create(:guideline_section, guideline: guideline, kind: "archived_document", body: body)
    guideline
  end

  let(:pages) do
    (["Catálogo Maestro de Guías de Práctica Clínica: GPC-IMSS-051-18",
      "Tratamiento quirúrgico de la obesidad en el adulto"] * 3).join("\n")
  end

  # The point of storing the document whole: improving the title heuristic must never
  # mean downloading 700 PDFs from a rate-limited archive a second time.
  it "renames from text already stored, without any network access" do
    guideline = archived(title: "IMSS-051-18", body: pages)

    expect(described_class.call.payload).to include(retitled: 1)
    expect(guideline.reload.title).to eq("Tratamiento quirúrgico de la obesidad en el adulto")
  end

  it "leaves a guideline whose title is already right alone" do
    archived(title: "Tratamiento quirúrgico de la obesidad en el adulto", body: pages)

    expect(described_class.call.payload).to include(unchanged: 1)
  end

  it "keeps the catalog key when the text still yields no readable title" do
    guideline = archived(title: "IMSS-051-18", body: "Página 3\nCENETEC\n")

    expect(described_class.call.payload).to include(unreadable: 1)
    expect(guideline.reload.title).to eq("IMSS-051-18")
  end

  it "counts an archived guideline with no stored document" do
    create(:guideline, source: "web_archive")

    expect(described_class.call.payload).to include(no_text: 1)
  end

  it "does not touch guidelines that came from the live site" do
    live = create(:guideline, source: "live_site", title: "El título vivo")
    create(:guideline_section, guideline: live, kind: "recommendation", body: pages)

    described_class.call

    expect(live.reload.title).to eq("El título vivo")
  end
end

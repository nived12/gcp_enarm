require "rails_helper"

RSpec.describe Gpc::Retitler do
  def archived(title:, body:, catalog_key: "IMSS-051-18")
    guideline = create(:guideline, source: "web_archive", title: title, catalog_key: catalog_key)
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

  # A cover the heuristic misreads is read once by hand, and that reading wins.
  it "prefers a title read off the cover by hand" do
    guideline = archived(title: "Médico Traumatólogo Ortopedista", body: pages, catalog_key: "IMSS-085-08")

    described_class.call

    expect(guideline.reload.title).to eq(
      "Diagnóstico y tratamiento del síndrome de hombro doloroso en primer nivel de atención"
    )
  end

  it "puts back a space the extraction dropped" do
    welded = (["Catálogo Maestro de Guías de Práctica Clínica: GPC-IMSS-051-18",
      "Diagnóstico y Tratamientode la obesidad en el adulto"] * 3).join("\n")
    create(:recommendation, text: ("Tratamiento de la obesidad. " * 5).strip)
    guideline = archived(title: "IMSS-051-18", body: welded)

    described_class.call

    expect(guideline.reload.title).to eq("Diagnóstico y Tratamiento de la obesidad en el adulto")
  end

  it "leaves a guideline whose title is already right alone" do
    archived(title: "Tratamiento quirúrgico de la obesidad en el adulto", body: pages)

    expect(described_class.call.payload).to include(unchanged: 1)
  end

  it "leaves a guideline that already carries its catalog key alone" do
    guideline = archived(title: "IMSS-051-18", body: "Página 3\nCENETEC\n")

    expect(described_class.call.payload).to include(unchanged: 1)
    expect(guideline.reload.title).to eq("IMSS-051-18")
  end

  # Tightening the extractor has to be able to remove a bad title, not only add a good
  # one. Otherwise a guideline named after a bibliography entry stays named after it.
  it "retracts a title the extractor will no longer vouch for" do
    guideline = archived(
      title: "20. Goble DJ, Bilateral facilitation of upper limb movements",
      body: "Página 3\nCENETEC\n"
    )

    expect(described_class.call.payload).to include(retracted: 1)
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

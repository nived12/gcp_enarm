require "rails_helper"

RSpec.describe Gpc::CatalogImporter do
  def entry(overrides = {})
    {
      catalog_key: "IMSS-028-22",
      title: "Atención y cuidados multidisciplinarios en el embarazo",
      institution: "imss",
      year: 2022,
      source: "live_site",
      external_id: "3079",
      catalog_url: "https://gpc.salud.gob.mx/DDIMBE",
      document_url: "https://gpc.salud.gob.mx/DDIMBE/DDIMBE/ContenidoGuia?DocumentoID=3079",
      specialty_labels: ["Gineco-Obstetricia"],
      levels_of_care: [1, 2]
    }.merge(overrides)
  end

  it "creates a guideline for an entry it has not seen" do
    response = described_class.call([entry])

    expect(response).to be_success
    expect(response.payload).to eq(created: 1, updated: 0, unchanged: 0)
    expect(Guideline.find_by(catalog_key: "IMSS-028-22")).to have_attributes(
      title: "Atención y cuidados multidisciplinarios en el embarazo",
      institution: "imss",
      year: 2022,
      levels_of_care: [1, 2]
    )
  end

  describe "re-running against an unchanged catalog" do
    before { described_class.call([entry]) }

    it "reports the row as unchanged and writes nothing but the timestamp" do
      guideline = Guideline.sole
      before_update = guideline.updated_at

      travel 1.hour do
        response = described_class.call([entry])

        expect(response.payload).to eq(created: 0, updated: 0, unchanged: 1)
        expect(guideline.reload.updated_at).to eq(before_update)
        expect(guideline.ingested_at).to be_within(1.minute).of(Time.current)
      end
    end

    it "does not create a duplicate" do
      expect { described_class.call([entry]) }.not_to change(Guideline, :count)
    end
  end

  describe "when the catalog republishes a guideline" do
    before { described_class.call([entry]) }

    it "updates the row and reports it as changed" do
      response = described_class.call([entry(title: "Título corregido", year: 2024)])

      expect(response.payload).to eq(created: 0, updated: 1, unchanged: 0)
      expect(Guideline.sole).to have_attributes(title: "Título corregido", year: 2024)
    end

    # ingested_at moving must not read as the guideline having changed, or every
    # run would invalidate every question generated from it.
    it "treats a new ingested_at alone as no change" do
      Guideline.sole.update_column(:ingested_at, 1.year.ago)

      expect(described_class.call([entry]).payload).to eq(created: 0, updated: 0, unchanged: 1)
    end
  end

  it "counts a mixed batch correctly" do
    described_class.call([entry])

    response = described_class.call(
      [
            entry,
            entry(catalog_key: "SS-160-22", institution: "health_ministry")
          ]
    )

    expect(response.payload).to eq(created: 1, updated: 0, unchanged: 1)
  end

  it "fails with the record's own errors when an entry is not valid" do
    response = described_class.call([entry(title: nil)])

    expect(response).to be_failure
    expect(response.errors.map(&:message)).to include(a_string_matching(/No se pudo guardar la guía/))
    expect(Guideline.count).to eq(0)
  end
end

require "rails_helper"

RSpec.describe Taxonomy::Seeder do
  describe "the taxonomy the app actually ships" do
    it "builds the seven blocks the convocatoria names" do
      described_class.call

      expect(Specialty.in_reading_order.pluck(:name)).to eq(
        ["Medicina Interna", "Pediatría", "Gineco-Obstetricia", "Cirugía General",
         "Salud Pública", "Urgencias", "Medicina Familiar"]
      )
    end

    it "marks the four troncales as core and the three contexts as cross-cutting" do
      described_class.call

      expect(Specialty.kind_core.count).to eq(4)
      expect(Specialty.kind_cross_cutting.count).to eq(3)
    end

    it "covers Cirugía General, which the live GPC catalog does not" do
      described_class.call

      surgery = Specialty.find_by(slug: "cirugia-general")

      expect(surgery.topics.count).to be >= 30
      expect(surgery.branches.pluck(:name)).to include("Trauma", "Urología", "Otorrinolaringología")
    end

    it "is idempotent, because it runs on every deploy" do
      described_class.call

      expect { described_class.call }.not_to change(Topic, :count)
    end
  end

  describe "reading a file" do
    let(:path) { Rails.root.join("tmp/spec-taxonomy-#{SecureRandom.hex(4)}.yml") }
    let(:minimal) do
      <<~YAML
        - name: Medicina Interna
          kind: core
          color_token: indigo
          branches:
            - name: Cardiología
              topics:
                - name: Infarto agudo de miocardio
                  aliases: [IAM, SICA]
                - name: Insuficiencia cardiaca
      YAML
    end

    after { FileUtils.rm_f(path) }

    def write(yaml) = File.write(path, yaml)

    it "derives slugs from names rather than reading them" do
      write(minimal)
      described_class.call(path)

      expect(Topic.pluck(:slug)).to contain_exactly("infarto-agudo-de-miocardio", "insuficiencia-cardiaca")
    end

    # The order in the file is the study plan's reading order, so it is deliberate.
    it "numbers positions from the order in the file" do
      write(minimal)
      described_class.call(path)

      expect(Topic.order(:position).pluck(:name))
        .to eq(["Infarto agudo de miocardio", "Insuficiencia cardiaca"])
    end

    it "stores aliases, and an empty list where there are none" do
      write(minimal)
      described_class.call(path)

      expect(Topic.find_by(slug: "infarto-agudo-de-miocardio").aliases).to eq(["IAM", "SICA"])
      expect(Topic.find_by(slug: "insuficiencia-cardiaca").aliases).to eq([])
    end

    it "reports what it changed on a re-run" do
      write(minimal)
      described_class.call(path)

      expect(described_class.call(path).payload)
        .to include(specialties_updated: 1, branches_updated: 1, topics_updated: 2)
    end

    it "fails on a missing file" do
      expect(described_class.call(path).errors.full_messages.first).to include("No existe")
    end

    it "fails without writing anything when the file describes something invalid" do
      write(minimal.sub("color_token: indigo", "color_token: no-es-un-token"))

      expect(described_class.call(path)).not_to be_success
      expect(Specialty.count).to eq(0)
    end
  end
end

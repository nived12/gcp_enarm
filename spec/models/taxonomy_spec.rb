require "rails_helper"

RSpec.describe "the taxonomy models" do
  describe Specialty do
    it "requires a unique slug" do
      create(:specialty, slug: "medicina-interna")
      duplicate = build(:specialty, slug: "medicina-interna")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors).to be_of_kind(:slug, :taken)
    end

    it "requires a name and a position" do
      expect(build(:specialty, name: nil)).not_to be_valid
      expect(build(:specialty, position: nil)).not_to be_valid
    end

    # The palette lives in CSS so dark mode stays a stylesheet concern; this column only
    # names which entry to use, and a name that is not an entry is a broken page.
    it "only accepts a colour that is a token in the stylesheet" do
      expect(build(:specialty, color_token: "indigo")).to be_valid
      expect(build(:specialty, color_token: "#ff0000")).not_to be_valid
    end

    it "reaches its topics through its branches" do
      specialty = create(:specialty)
      topic = create(:topic, branch: create(:branch, specialty: specialty))

      expect(specialty.topics).to eq([topic])
    end

    it "takes its branches and their topics with it when destroyed" do
      specialty = create(:specialty)
      create(:topic, branch: create(:branch, specialty: specialty))

      expect { specialty.destroy }.to change(Topic, :count).by(-1).and change(Branch, :count).by(-1)
    end

    describe ".for_setting_code" do
      it "finds the context a generation prompt's setting code names, whatever its case or padding" do
        emergency = create(:emergency_setting)
        family = create(:family_medicine_setting)
        public_health = create(:public_health_setting)

        expect(described_class.for_setting_code("emergency")).to eq(emergency)
        expect(described_class.for_setting_code(" Family_Medicine ")).to eq(family)
        expect(described_class.for_setting_code(:public_health)).to eq(public_health)
      end

      it "leaves an unknown or missing code unknown" do
        create(:emergency_setting)

        expect(described_class.for_setting_code("hospital_ward")).to be_nil
        expect(described_class.for_setting_code(nil)).to be_nil
      end

      it "never resolves to a troncal that happens to carry the slug" do
        create(:specialty, slug: "urgencias", kind: "core")

        expect(described_class.for_setting_code("emergency")).to be_nil
      end
    end

    it "names its setting code, and a troncal has none" do
      expect(build(:emergency_setting).setting_code).to eq("emergency")
      expect(build(:specialty).setting_code).to be_nil
    end
  end

  describe Branch do
    it "requires a unique slug, a name and a position" do
      create(:branch, slug: "cardiologia")

      expect(build(:branch, slug: "cardiologia")).not_to be_valid
      expect(build(:branch, name: nil)).not_to be_valid
      expect(build(:branch, position: nil)).not_to be_valid
    end
  end

  describe Topic do
    it "requires a unique slug, a name and a position" do
      create(:topic, slug: "infarto")

      expect(build(:topic, slug: "infarto")).not_to be_valid
      expect(build(:topic, name: nil)).not_to be_valid
      expect(build(:topic, position: nil)).not_to be_valid
    end

    it "reaches its specialty through its branch" do
      specialty = create(:specialty)
      topic = create(:topic, branch: create(:branch, specialty: specialty))

      expect(topic.specialty).to eq(specialty)
    end

    describe "#search_phrases" do
      # A phrase that contains another is the more specific match, so it is tried first.
      it "offers every name it answers to, longest first" do
        topic = build(:topic, name: "Infarto agudo de miocardio", aliases: ["IAM", "síndrome coronario agudo"])

        expect(topic.search_phrases).to eq(["Infarto agudo de miocardio", "síndrome coronario agudo", "IAM"])
      end

      it "drops blanks rather than matching everything on an empty phrase" do
        expect(build(:topic, name: "Gota", aliases: ["", "  "]).search_phrases).to eq(["Gota"])
      end
    end

    it "separates the topics a guideline reaches from the ones nothing does" do
      linked = create(:topic)
      unlinked = create(:topic)
      create(:guideline_topic, topic: linked)

      expect(described_class.linked).to eq([linked])
      expect(described_class.unlinked).to eq([unlinked])
    end
  end

  describe GuidelineTopic do
    it "holds one link per guideline and topic" do
      link = create(:guideline_topic)
      duplicate = build(:guideline_topic, guideline: link.guideline, topic: link.topic)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors).to be_of_kind(:guideline_id, :taken)
    end

    it "keeps relevance a proportion" do
      expect(build(:guideline_topic, relevance: 0.5)).to be_valid
      expect(build(:guideline_topic, relevance: 1.5)).not_to be_valid
      expect(build(:guideline_topic, relevance: nil)).not_to be_valid
    end

    it "selects the links strong enough to build a study day from" do
      confident = create(:guideline_topic, relevance: 0.4)
      create(:guideline_topic, relevance: 0.05)

      expect(described_class.confident).to eq([confident])
    end
  end
end

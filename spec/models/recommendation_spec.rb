require "rails_helper"

RSpec.describe Recommendation do
  it "requires the text it will be cited for" do
    recommendation = build(:recommendation, text: nil)

    expect(recommendation).not_to be_valid
    expect(recommendation.errors).to be_of_kind(:text, :blank)
  end

  it "requires the grading strip even when it could not be split" do
    expect(build(:recommendation, label: nil)).not_to be_valid
  end

  it "rejects two statements at the same position in one section" do
    section = create(:guideline_section)
    create(:recommendation, guideline_section: section, position: 1)

    expect(build(:recommendation, guideline_section: section, position: 1)).not_to be_valid
  end

  it "reaches its guideline through its section" do
    guideline = create(:guideline)
    recommendation = create(:recommendation, guideline_section: create(:guideline_section, guideline: guideline))

    expect(recommendation.guideline).to eq(guideline)
  end

  describe "#cited_as" do
    it "reads as grade, scale and study" do
      expect(build(:recommendation).cited_as).to eq("A · NICE · Hong K, 2021")
    end

    it "leaves out what the strip did not say" do
      expect(build(:recommendation, citation: nil).cited_as).to eq("A · NICE")
    end

    it "falls back to the strip when none of it could be split" do
      unparsed = build(:recommendation, grade: nil, scale: nil, citation: nil, label: "FUERTE SHRE 2022")

      expect(unparsed.cited_as).to eq("FUERTE SHRE 2022")
    end
  end

  it "selects only statements that say what to do" do
    create(:recommendation, guideline_section: create(:guideline_section, kind: "evidence"))
    actionable = create(:recommendation, guideline_section: create(:guideline_section, kind: "recommendation"))

    expect(described_class.actionable).to eq([actionable])
  end

  it "selects by grading scale" do
    nice = create(:recommendation, scale: "NICE")
    create(:recommendation, scale: "GRADE")

    expect(described_class.with_scale("NICE")).to eq([nice])
  end
end

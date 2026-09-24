require "rails_helper"

RSpec.describe LandingStats do
  it "counts only what a student can practise, and the mock exam's length" do
    published = create(:published_case)
    create(:published_case, guideline: published.guideline)
    create(:published_case, status: "draft")

    counts = described_class.current

    expect(counts.cases).to eq(2)
    expect(counts.questions).to eq(4)
    expect(counts.guidelines).to eq(1)
    expect(counts.mock_questions).to eq(280)
  end
end

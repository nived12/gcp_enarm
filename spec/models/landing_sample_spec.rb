require "rails_helper"

RSpec.describe LandingSample do
  def published(year: 2022, **attributes)
    create(:published_case, guideline: create(:guideline, year: year), **attributes)
  end

  it "draws nothing from an empty bank" do
    expect(described_class.draw).to be_nil
  end

  it "only offers a published Spanish case whose every question cites its recommendation" do
    shown = published
    create(:clinical_case, status: "draft")
    published(questions_count: 1)
    published(locale: "en")
    published(stem: "Paciente " * 120)
    published.questions.first.update_columns(recommendation_id: nil)
    published.questions.last.update_columns(source_quote: "")

    expect(described_class.pool_keys).to eq([shown.export_key])
  end

  it "draws the case a visitor asked for, and offers a different one next" do
    first = published
    second = published

    draw = described_class.draw(first.export_key)

    expect(draw.clinical_case).to eq(first)
    expect(draw.next_key).to eq(second.export_key)
  end

  it "draws at random when the case asked for is not in the pool" do
    only = published

    draw = described_class.draw("no-such-case")

    expect(draw.clinical_case).to eq(only)
    expect(draw.next_key).to be_nil
  end

  it "fills the pool from the most recent guidelines first" do
    stub_const("LandingSample::POOL_SIZE", 1)
    published(year: 2012)
    recent = published(year: 2024)

    expect(described_class.pool_keys).to eq([recent.export_key])
  end

  it "puts the featured cases ahead of the rest" do
    stub_const("LandingSample::POOL_SIZE", 2)
    featured = published(year: 2010)
    published(year: 2024)
    recent = published(year: 2025)
    stub_const("LandingSample::FEATURED", [featured.export_key])

    expect(described_class.pool_keys).to eq([featured.export_key, recent.export_key])
  end
end

require "rails_helper"

RSpec.describe StudyPlans::Fitter do
  let(:monday) { Date.new(2026, 10, 5) }

  def dates(count)
    Array.new(count) { |i| monday + i }
  end

  def slot(kind, pass = 1, topics = [])
    StudyPlans::Slot.for(kind, pass, nil, topics)
  end

  def kinds(placed)
    placed.map { |_date, placed_slot| placed_slot.kind }
  end

  it "has nothing to place when nothing is left" do
    expect(described_class.fit([], dates(3))).to eq([])
  end

  it "gives each slot the next date, in order" do
    slots = [slot("topics", 1, [1]), slot("assessment")]

    expect(described_class.fit(slots, dates(2))).to eq([[monday, slots[0]], [monday + 1, slots[1]]])
  end

  it "turns spare dates into reviews just before the final simulacro" do
    placed = described_class.fit([slot("topics", 3, [1]), slot("assessment", 3)], dates(4))

    expect(kinds(placed)).to eq(%w[topics review review assessment])
    expect(placed.map { |_date, placed_slot| placed_slot.pass_number }.uniq).to eq([3])
  end

  it "gives up the slack first, then practice days, and keeps the final day" do
    slots = [
      slot("topics", 1, [1]), slot("case_workshop"), slot("catch_up"), slot("review"), slot("assessment"),
      slot("topics", 2, [2]), slot("catch_up", 2), slot("review", 2)
    ]

    expect(kinds(described_class.fit(slots, dates(6)))).to eq(%w[topics case_workshop review assessment topics review])
    expect(kinds(described_class.fit(slots, dates(4)))).to eq(%w[topics assessment topics review])
    expect(kinds(described_class.fit(slots, dates(3)))).to eq(%w[topics topics review])
  end

  it "merges topic days of the latest pass, lightest pair first, and never across passes" do
    slots = [
      slot("topics", 1, [1]), slot("topics", 1, [2]),
      slot("topics", 2, [3, 4]), slot("topics", 2, [5]), slot("topics", 2, [6]), slot("assessment", 2)
    ]

    placed = described_class.fit(slots, dates(5))

    expect(placed.map { |_date, placed_slot| placed_slot.topic_ids }).to eq([[1], [2], [3, 4], [5, 6], []])
    expect(described_class.fit(slots, dates(3)).map { |_date, placed_slot| placed_slot.topic_ids })
      .to eq([[1, 2], [3, 4, 5, 6], []])
  end

  it "keeps a started quiz with the day it merges into" do
    slots = [slot("topics", 1, [1]), slot("topics", 1, [2]).with(exam_id: 9)]

    expect(described_class.fit(slots, dates(1)).first.last).to have_attributes(topic_ids: [1, 2], exam_id: 9)
  end

  it "gives up when not even merging leaves a date for every slot" do
    slots = [slot("topics", 1, [1]), slot("topics", 2, [2])]

    expect(described_class.fit(slots, dates(1))).to be_nil
    expect(described_class.fit(slots, [])).to be_nil
  end
end

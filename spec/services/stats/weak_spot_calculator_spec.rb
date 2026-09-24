require "rails_helper"

RSpec.describe Stats::WeakSpotCalculator do
  let(:user) { create(:user) }
  let(:topics) { create_list(:topic, 4) }

  # A one-question case in `topic`, sat once with `outcome`.
  def answer(topic, outcome, **options)
    kase = create(:published_case, topic: topic, questions_count: 1)
    sit(user, kase, [outcome], **options)
    kase
  end

  def spots
    described_class.call(user).payload.spots
  end

  it "says nothing before ten questions" do
    9.times { answer(topics[0], :wrong) }

    result = described_class.call(user).payload

    expect(result).to have_attributes(spots: [], asked: 9, enough_data?: false)
  end

  it "names nothing when no topic is below the student's own mean" do
    10.times { |index| answer(topics[index % 2], :right) }

    expect(described_class.call(user).payload).to have_attributes(spots: [], enough_data?: true)
  end

  it "names the topics below the student's mean, weakest first, measured against themselves" do
    3.times { answer(topics[0], [:wrong, "did_not_know"]) }
    answer(topics[0], :right)
    2.times { answer(topics[1], [:wrong, "did_not_know"]) }
    2.times { answer(topics[1], :right) }
    4.times { answer(topics[2], :right) }

    expect(spots.map(&:topic)).to eq(topics.first(2))
    expect(spots.first).to have_attributes(asked: 4)
    expect(spots.first.excess).to be > spots.second.excess
  end

  it "weighs a knowledge gap over an unknown miss, and an unknown miss over a misreading" do
    [topics[0], topics[1], topics[2]].zip(["did_not_know", nil, "misread_case"]).each do |topic, reason|
      2.times { answer(topic, [:wrong, reason]) }
      answer(topic, :right)
    end
    4.times { answer(topics[3], :right) }

    gaps = described_class.new(user).call.payload.spots.to_h { |spot| [spot.topic, spot.gap] }

    expect(gaps[topics[0]]).to be > gaps[topics[1]]
    expect(gaps.fetch(topics[2], 0)).to be < gaps[topics[1]]
  end

  it "counts the same wrong option chosen twice as a settled misconception" do
    [topics[0], topics[1]].each_with_index do |topic, index|
      kase = create(:published_case, topic: topic, questions_count: 1)
      wrong = kase.questions.first.answer_options.reject(&:correct?)
      sit(user, kase, [[:wrong, "did_not_know"]], option: wrong[0])
      sit(user, kase, [[:wrong, "did_not_know"]], option: wrong[index])
    end
    8.times { answer(topics[2], :right) }

    expect(spots.map(&:topic)).to eq([topics[0], topics[1]])
  end

  it "lets old misses fade behind recent ones" do
    travel_to(60.days.ago) { 2.times { answer(topics[0], [:wrong, "did_not_know"]) } }
    2.times { answer(topics[1], [:wrong, "did_not_know"]) }
    8.times { answer(topics[2], :right) }

    expect(spots.first.topic).to eq(topics[1])
  end

  it "leaves out discarded exams, unfinished blanks and a topic met only once" do
    10.times { answer(topics[2], :right) }
    answer(topics[0], [:wrong, "did_not_know"])
    3.times { answer(topics[1], [:wrong, "did_not_know"]).then { user.exams.last.discard! } }
    sit(user, create(:published_case, topic: topics[1], questions_count: 1), [nil])

    expect(spots).to eq([])
  end

  it "counts a finished exam's blank as an unknown miss" do
    10.times { answer(topics[2], :right) }
    2.times { answer(topics[0], nil, finish: true) }

    expect(spots.map(&:topic)).to eq([topics[0]])
  end

  context "with confidence" do
    def gaps
      described_class.call(user).payload.spots.to_h { |spot| [spot.topic, spot.gap] }
    end

    it "counts a right guess as an unexplained miss and a right but unsure answer as a slip" do
      3.times { answer(topics[0], :right, confidence: "guess") }
      3.times { answer(topics[1], :right, confidence: "unsure") }
      4.times { answer(topics[2], :right, confidence: "sure") }
      4.times { answer(topics[3], :right) }

      expect(spots.map(&:topic)).to eq(topics.first(2))
      expect(gaps[topics[0]]).to be > gaps[topics[1]]
    end

    it "weighs a miss the student was sure of as a misconception" do
      [topics[0], topics[1]].zip(["sure", nil]).each do |topic, confidence|
        2.times { answer(topic, [:wrong, "did_not_know"], confidence: confidence) }
        answer(topic, :right)
      end
      8.times { answer(topics[2], :right) }

      expect(spots.map(&:topic)).to eq(topics.first(2))
      expect(gaps[topics[0]]).to be > gaps[topics[1]]
    end

    it "reads a miss the student was unsure of, or guessed, as one with no confidence" do
      [topics[0], topics[1], topics[2]].zip(["unsure", "guess", nil]).each do |topic, confidence|
        2.times { answer(topic, [:wrong, "did_not_know"], confidence: confidence) }
      end
      8.times { answer(topics[3], :right) }

      expect(gaps.values).to all(be_within(1e-6).of(gaps.values.first))
    end
  end

  context "with settings" do
    let(:emergency) { create(:emergency_setting) }
    let(:core) { create(:specialty) }

    # A one-question case in a topic of its own, so only its areas can gather a spot.
    def answer_in(outcome, specialty: nil, setting: nil)
      kase = create(:published_case, topic: create(:topic), specialty: specialty, setting: setting, questions_count: 1)
      sit(user, kase, [outcome])
    end

    it "names a setting whose cases, about it or set in it, sit below the student's mean" do
      answer_in([:wrong, "did_not_know"], specialty: emergency, setting: emergency)
      answer_in([:wrong, "did_not_know"], specialty: core, setting: emergency)
      answer_in([:wrong, "did_not_know"], specialty: emergency)
      2.times { answer_in([:wrong, "did_not_know"], specialty: core) }
      8.times { answer(topics[0], :right) }

      spot = spots.sole
      expect(spot).to have_attributes(setting: emergency, topic: nil, area: emergency, asked: 3)
    end

    it "counts a question toward its topic and its setting, and toward the mean once" do
      3.times { answer(topics[0], [:wrong, "did_not_know"]).update!(setting: emergency) }
      8.times { answer(topics[1], :right) }

      result = described_class.call(user).payload

      expect(result.spots.map(&:area)).to contain_exactly(topics[0], emergency)
      expect(result.spots.map(&:asked)).to eq([3, 3])
      expect(result.asked).to eq(11)
      expect(result.mean_gap).to be_within(0.001).of(3.0 / 11)
    end
  end
end

require "rails_helper"

RSpec.describe ReviewCard do
  let(:today) { Date.new(2026, 9, 23) }

  def card
    build(:review_card, :pearl)
  end

  it "steps through SM-2's intervals — one day, six, then the last times the ease" do
    subject = card
    intervals = Array.new(4) { subject.schedule(4, on: today).interval_days }

    expect(intervals).to eq([1, 6, 15, 38])
    expect(subject).to have_attributes(repetitions: 4, reviews_count: 4, ease_factor: 2.5, due_on: today + 38)
  end

  it "starts a card over from one day on a lapse, and takes ease away" do
    subject = card
    3.times { subject.schedule(5, on: today) }
    subject.schedule(1, on: today)

    expect(subject).to have_attributes(interval_days: 1, repetitions: 0, lapses: 1, last_reviewed_on: today)
    expect(subject.ease_factor).to be_within(0.001).of(2.26)
  end

  it "never lets the ease drop below 1.3" do
    subject = card
    10.times { subject.schedule(0, on: today) }

    expect(subject.ease_factor).to eq(1.3)
  end

  it "keeps a pass at quality 3 on schedule while lowering its ease" do
    subject = card.schedule(3, on: today)

    expect(subject).to have_attributes(interval_days: 1, repetitions: 1, lapses: 0)
    expect(subject.ease_factor).to be_within(0.001).of(2.36)
  end

  it "refuses a quality outside SM-2's scale" do
    expect { card.schedule(6, on: today) }.to raise_error(ArgumentError)
  end

  it "resets to a card never reviewed, keeping what it points at" do
    subject = card.schedule(1, on: today).reset

    expect(subject).to have_attributes(ease_factor: 2.5, interval_days: 0, repetitions: 0, lapses: 0, reviews_count: 0)
    expect(subject.recommendation).to be_present
  end

  it "points at exactly one thing, as the database insists" do
    kase = create(:published_case)
    both = build(:review_card, :pearl, clinical_case: kase)

    expect { both.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid, /review_cards_one_subject/)
  end

  it "shows only published cases as due, and splits cases from pearls" do
    user = create(:user)
    live = create(:review_card, :case, user: user, due_on: today)
    withdrawn = create(:review_card, :case, user: user, due_on: today)
    withdrawn.clinical_case.update!(status: "retired")
    pearl = create(:review_card, :pearl, user: user, due_on: today + 1)

    expect(described_class.published_cases).to eq([live])
    expect(described_class.pearls).to eq([pearl])
    expect(described_class.due(today)).to contain_exactly(live, withdrawn)
  end
end

require "rails_helper"

RSpec.describe Reviews::CaseScheduler do
  let(:user) { create(:user) }
  let(:kase) { create(:published_case, questions_count: 2) }
  let(:today) { user.study_date }

  def sit(outcomes, **options)
    super(user, kase, outcomes, **options)
  end

  def card
    ReviewCard.find_by(user: user, clinical_case: kase)
  end

  it "leaves a case answered right out of the deck" do
    sit(%i[right right])

    expect(card).to be_nil
  end

  it "brings a missed case back tomorrow, as a lapse when no reason was given" do
    sit(%i[right wrong])

    expect(card).to have_attributes(due_on: today + 1, lapses: 1, repetitions: 0)
    expect(card.ease_factor).to be_within(0.001).of(2.18)
  end

  it "keeps a misread or timed-out case's progress: it was not a gap in knowledge" do
    exam = sit(%i[right wrong])
    exam.answers.find_by(correct: false).update!(error_reason: "misread_case")

    expect(card).to have_attributes(due_on: today + 1, lapses: 0, repetitions: 1)
    expect(card.ease_factor).to be_within(0.001).of(2.36)
  end

  describe "what the student said about their confidence" do
    it "puts a case answered right by guessing in the deck, as a lapse" do
      sit(%i[right right]).answers.first.update!(confidence: "guess")

      expect(card).to have_attributes(due_on: today + 1, lapses: 1, repetitions: 0)
    end

    it "puts a case answered right with doubt in the deck, as a pass that costs ease" do
      sit(%i[right right]).answers.first.update!(confidence: "unsure")

      expect(card).to have_attributes(due_on: today + 1, lapses: 0, repetitions: 1)
      expect(card.ease_factor).to be_within(0.001).of(2.36)
    end

    it "leaves a case answered right and sure out of the deck" do
      sit(%i[right right]).answers.each { |answer| answer.update!(confidence: "sure") }

      expect(card).to be_nil
    end

    it "grades a miss by its reason, not by the confidence it was given with" do
      exam = sit(%i[wrong right])
      exam.answers.find_by(correct: false).update!(confidence: "guess", error_reason: "misread_case")

      expect(card).to have_attributes(lapses: 0, repetitions: 1)
    end
  end

  it "grades an attempt by its worst miss, and not knowing costs the most ease" do
    sit([[:wrong, "did_not_know"], [:wrong, "ran_out_of_time"]])

    expect(card.ease_factor).to be_within(0.001).of(1.96)
  end

  it "moves the case further out each time it is answered right again" do
    sit(%i[wrong right])
    travel 1.day do
      sit(%i[right right])
      expect(card).to have_attributes(due_on: user.study_date + 1, repetitions: 1, reviews_count: 2)
    end
    travel 2.days do
      sit(%i[right right])
      expect(card).to have_attributes(due_on: user.study_date + 6, repetitions: 2)
    end
  end

  it "does not grade an attempt until it is over" do
    sit([:right, nil])

    expect(card).to be_nil
  end

  it "waits for the single page to be finished, then counts its blanks as misses" do
    exam = sit([:right, nil], timing: "at_end")
    expect(card).to be_nil

    exam.complete!

    expect(card).to have_attributes(due_on: today + 1, lapses: 1)
  end

  it "leaves out a case the student never reached, as when the clock ran out" do
    exam = sit([nil, nil], timing: "at_end")

    exam.complete!

    expect(card).to be_nil
  end

  it "drops the case again when the single page's miss is changed to a right answer" do
    exam = sit(%i[right wrong], timing: "at_end", finish: true)
    expect(card).to be_present

    answer = exam.answers.find_by(correct: false)
    answer.update!(correct: true, answer_option: answer.exam_question.question.correct_option)

    expect(card).to be_nil
  end

  it "counts a discarded exam's misses: the case was still read and missed" do
    sit(%i[wrong wrong]).discard!

    expect(card).to be_present
  end

  it "ignores right answers from before the first miss" do
    sit(%i[right right])
    travel 1.day do
      sit(%i[wrong right])
      expect(card).to have_attributes(reviews_count: 1, due_on: user.study_date + 1)
    end
  end
end

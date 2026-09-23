require "rails_helper"

RSpec.describe Pearls::CardPicker do
  let(:user) { create(:user) }

  def statement(kase, text = "Se recomienda iniciar amoxicilina durante 10 días en la otitis media aguda.")
    create(:recommendation, guideline_section: kase.questions.first.recommendation.guideline_section, text: text)
  end

  # The factory's own statement is a pearl too; this case's is not, so each example
  # decides exactly which statements are in the pool.
  def quiet_case
    create(:published_case, questions_count: 1).tap do |kase|
      kase.questions.first.recommendation.update!(text: "La mayoría de los pacientes mejora sin tratamiento.")
    end
  end

  def pick
    described_class.call(user).payload
  end

  it "has nothing to offer when no statement can be a pearl" do
    expect(pick).to be_nil
  end

  it "offers a pearl due for review before a new one" do
    kase = quiet_case
    statement(kase)
    held = statement(kase, "Se recomienda vigilar la glucosa cada 4 horas en el posoperatorio.")
    create(:review_card, user: user, recommendation: held, due_on: user.study_date)

    expect(pick.recommendation).to eq(held)
  end

  it "skips a card whose statement no longer has a phrase to hide, and one not yet due" do
    kase = quiet_case
    fresh = statement(kase)
    create(:review_card, user: user, recommendation: statement(kase, "Se recomienda."), due_on: user.study_date)
    create(:review_card, user: user, recommendation: statement(kase, "Dar 5 mg al día."), due_on: user.study_date + 1)

    expect(pick.recommendation).to eq(fresh)
  end

  it "takes new pearls from the guidelines behind missed cases, then seen ones, then the rest" do
    missed, seen, other = Array.new(3) { quiet_case }
    sit(user, missed, [:wrong])
    sit(user, seen, [:right])
    [other, seen, missed].each { |kase| statement(kase) }

    guidelines = Array.new(3) do
      pick.recommendation.tap { |r| create(:review_card, user: user, recommendation: r, due_on: user.study_date + 9) }
          .guideline
    end

    expect(guidelines).to eq([missed, seen, other].map(&:guideline))
  end

  it "does not count a case only drawn into an exam as met" do
    drawn, other = Array.new(2) { quiet_case }
    drawn.guideline.update!(year: 2001)
    other.guideline.update!(year: Date.current.year)
    sit(user, drawn, [nil])
    [drawn, other].each { |kase| statement(kase) }

    expect(pick.recommendation.guideline).to eq(other.guideline)
  end

  it "reads the pool in batches until one statement makes a pearl" do
    stub_const("#{described_class}::BATCH", 1)
    sit(user, quiet_case, [:wrong])
    statement(quiet_case)

    expect(pick.recommendation.text).to include("amoxicilina")
  end
end

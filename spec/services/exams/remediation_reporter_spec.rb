require "rails_helper"

RSpec.describe Exams::RemediationReporter do
  let(:user) { create(:user) }
  let(:shaky) { create(:topic, name: "Otitis media") }
  let(:solid) { create(:topic, name: "Crisis hipertensiva") }

  # Twenty questions on ten two-question cases: `shaky` goes 1 of 4, `solid` 16 of 16.
  def exam_with(reasons: [nil, nil, nil], mode: "custom", finish: true, extra: 0)
    exam = create(:exam, user: user, mode: mode, question_count: 1)
    first, second = create_list(:published_case, 2, topic: shaky, questions_count: 2)
    sit(user, first, [[:wrong, reasons[0]], [:wrong, reasons[1]]], exam: exam)
    sit(user, second, [[:wrong, reasons[2]], :right], exam: exam)
    (8 + extra).times do
      sit(user, create(:published_case, topic: solid, questions_count: 2), %i[right right], exam: exam)
    end
    exam.complete! if finish
    exam
  end

  def report(exam)
    described_class.call(exam).payload
  end

  it "names the topic that went worse than the exam, with the sections behind its misses" do
    exam = exam_with

    weakness = report(exam).sole

    expect(weakness).to have_attributes(topic: shaky, correct: 1, asked: 4)
    expect(weakness.percentage).to eq(25.0)
    expect(weakness.readings.map(&:misses)).to eq([2, 1])
    expect(weakness.readings.first.guideline).to eq(weakness.readings.first.section.guideline)
  end

  it "sends no one to read for a misreading or a timed-out miss, but does for an unknown one" do
    readings = report(exam_with(reasons: ["misread_case", "ran_out_of_time", nil])).sole.readings

    expect(readings.map(&:misses)).to eq([1])
  end

  it "waits for the exam to be finished and long enough to mean something" do
    expect(report(exam_with(finish: false))).to eq([])
    short = create(:exam, user: user, question_count: 1)
    sit(user, create(:published_case, topic: shaky, questions_count: 2), %i[wrong wrong], exam: short, finish: true)
    expect(report(short)).to eq([])
  end

  it "always reports on an exam-length mode, however short the bank made it" do
    exam = create(:exam, user: user, mode: "full_exam", question_count: 1)
    sit(user, create(:published_case, topic: shaky, questions_count: 2), %i[wrong wrong], exam: exam)
    sit(user, create(:published_case, topic: solid, questions_count: 2), %i[right right], exam: exam, finish: true)

    expect(report(exam).map(&:topic)).to eq([shaky])
  end

  it "has nothing to say about cases filed under no topic" do
    exam = create(:exam, user: user, mode: "full_exam", question_count: 1)
    sit(user, create(:published_case, questions_count: 2), %i[wrong wrong], exam: exam, finish: true)

    expect(report(exam)).to eq([])
  end
end

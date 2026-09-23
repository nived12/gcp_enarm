require "rails_helper"

RSpec.describe StudyPlanDay do
  let(:plan) { create(:study_plan) }
  let(:specialty) { create(:specialty) }
  let(:with_cases) { create(:topic, branch: create(:branch, specialty: specialty)) }
  let(:without_cases) { create(:topic) }

  before { create(:published_case, topic: with_cases, specialty: specialty) }

  def day(kind = "topics", **attributes)
    create(:study_plan_day, study_plan: plan, kind: kind, specialty: specialty, **attributes)
  end

  it "is done when its quiz is finished, or when marked on a day without one" do
    exam = create(:exam, user: plan.user)
    quiz_day = day(exam: exam)

    expect(quiz_day).not_to be_done
    exam.update!(status: "completed")
    expect(quiz_day.reload).to be_done
    expect(day(completed_at: Time.current)).to be_done
    expect(day).not_to be_done
  end

  it "quizzes only the day's topics that have published cases" do
    topics_day = day
    topics_day.day_topics.create!(topic: with_cases, position: 1)
    topics_day.day_topics.create!(topic: without_cases, position: 2)
    reading_day = day
    reading_day.day_topics.create!(topic: without_cases, position: 1)

    expect(topics_day.topics).to eq([with_cases, without_cases])
    expect(topics_day).to be_quiz
    expect(topics_day.exam_request).to eq(mode: "custom", filters: { topic_ids: [with_cases.id], question_count: 10 })
    expect(reading_day).not_to be_quiz
  end

  it "asks the exam builder for the right draw on each kind of day" do
    expect(day("case_workshop").exam_request)
      .to eq(mode: "custom", filters: { specialty_ids: [specialty.id], question_count: 20 })
    expect(day("review").exam_request).to eq(mode: "custom", filters: { question_count: 20 })
    expect(day("assessment").exam_request).to eq(mode: "full_exam", filters: {})
    expect(day("review")).to be_quiz
    expect(day("catch_up")).not_to be_quiz
  end

  it "belongs to one of three passes" do
    expect(build(:study_plan_day, pass_number: 4)).not_to be_valid
  end
end

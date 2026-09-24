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

  it "knows how long each kind of day's quiz is" do
    expect(%w[topics case_workshop review assessment].map { |kind| day(kind).question_count }).to eq([10, 20, 20, 280])
  end

  describe "a day of one of the three contexts" do
    let(:emergency) { create(:emergency_setting) }
    let(:emergency_topic) { create(:topic, branch: create(:branch, specialty: emergency)) }

    def context_day(specialty = emergency)
      create(:study_plan_day, study_plan: plan, kind: "topics", specialty: specialty).tap do |topics_day|
        topics_day.day_topics.create!(topic: emergency_topic, position: 1)
      end
    end

    it "is a reading day while nothing is about its topics or set in it" do
      expect(context_day).not_to be_quiz
      expect(context_day.setting_cases).to be_empty
    end

    it "quizzes the cases set in it when its own topics have none" do
      set_there = create(:published_case, specialty: specialty, setting: emergency)

      expect(context_day).to be_quiz
      expect(context_day.setting_cases).to eq([set_there])
      expect(context_day.exam_request).to eq(
        mode: "custom", filters: { topic_ids: [], question_count: 10, also_setting_ids: [emergency.id] }
      )
    end

    it "counts only published cases set in it" do
      create(:published_case, specialty: specialty, setting: emergency, status: "retired")

      expect(context_day).not_to be_quiz
    end

    it "leaves a troncal's day to its topics, whatever its cases' settings" do
      create(:published_case, specialty: specialty, setting: emergency)
      topics_day = day
      topics_day.day_topics.create!(topic: without_cases, position: 1)

      expect(topics_day.setting_cases).to be_empty
      expect(topics_day).not_to be_quiz
    end

    it "adds nothing to a workshop, which already draws the whole area" do
      create(:published_case, specialty: specialty, setting: emergency)

      expect(day("case_workshop", specialty: emergency).setting_cases).to be_empty
    end
  end

  it "belongs to one of three passes" do
    expect(build(:study_plan_day, pass_number: 4)).not_to be_valid
  end
end

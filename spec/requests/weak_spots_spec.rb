require "rails_helper"

RSpec.describe "Weak spots", type: :request do
  let(:student) { create(:user) }
  let(:shaky) { create(:topic, name: "Otitis media") }
  let(:solid) { create(:topic, name: "Crisis hipertensiva") }

  before { post session_path, params: { email: student.email, password: "contrasena-segura" } }

  def answer(topic, outcome)
    sit(student, create(:published_case, topic: topic, questions_count: 1), [outcome])
  end

  it "asks for more answers before naming weak spots" do
    create(:published_case)

    get new_exam_path(section: "custom")

    expect(response.body).to include(
      I18n.t("weak_spots.preset.title"), I18n.t("weak_spots.preset.not_enough", minimum: 10),
      I18n.t("exams.new.custom.submit")
    )
  end

  it "says so when nothing is below the student's average" do
    10.times { answer(solid, :right) }

    get new_exam_path(section: "custom")

    expect(response.body).to include(I18n.t("weak_spots.preset.none"))
  end

  it "names the weak topics and starts a quiz from them" do
    3.times { answer(shaky, [:wrong, "did_not_know"]) }
    8.times { answer(solid, :right) }

    get new_exam_path(section: "custom")
    expect(response.body).to include("Otitis media", I18n.t("weak_spots.preset.start", count: 20))
    expect(response.body).not_to include("Crisis hipertensiva, ", I18n.t("weak_spots.preset.setting_overlap"))

    post exams_path, params: { mode: "weak_spots" }
    exam = Exam.last
    expect(exam).to have_attributes(mode: "weak_spots", filters: { "interleave" => true, "topic_ids" => [shaky.id] })
    expect(response).to redirect_to(exam_question_path(exam, 1))
  end

  it "names a weak setting beside the topics, says they share questions, and quizzes its area" do
    emergency = create(:emergency_setting)
    3.times do
      sit(
        student, create(:published_case, topic: create(:topic), setting: emergency, questions_count: 1),
        [[:wrong, "did_not_know"]]
      )
    end
    8.times { answer(solid, :right) }

    get new_exam_path(section: "custom")
    expect(response.body).to include("Urgencias", I18n.t("weak_spots.preset.setting_overlap"))

    post exams_path, params: { mode: "weak_spots" }
    expect(Exam.last.filters).to eq("interleave" => true, "setting_ids" => [emergency.id])
  end

  it "sends the student back to the custom section when there is nothing to target" do
    post exams_path, params: { mode: "weak_spots" }

    expect(response).to redirect_to(new_exam_path(section: "custom"))
    expect(flash[:alert]).to eq(I18n.t("weak_spots.none"))
  end
end

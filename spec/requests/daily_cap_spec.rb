require "rails_helper"

# The free tier's daily allowance, where a student meets it: starting an exam and
# answering inside one. Both end on the pricing page, with the reason on top.
RSpec.describe "Free daily allowance", type: :request do
  let(:student) { create(:user, :trial_expired) }

  before do
    allow(SubscriptionAccess).to receive(:free_daily_questions).and_return(1)
    create(:published_case, questions_count: 2)
    post session_path, params: { email: student.email, password: "contrasena-segura" }
  end

  def answer_first_question(exam)
    exam_question = exam.exam_questions.find_by!(position: 1)
    post exam_question_answer_path(exam, 1),
      params: { answer_option_id: exam_question.question.answer_options.first.id }
  end

  it "stops an answer past the allowance and shows the plans" do
    post exams_path, params: { mode: "quick_quiz" }
    exam = Exam.last
    answer_first_question(exam)

    exam_question = exam.exam_questions.find_by!(position: 2)
    exam.update!(feedback_timing: "at_end")
    post exam_question_answer_path(exam, 2),
      params: { answer_option_id: exam_question.question.answer_options.first.id }

    expect(response).to redirect_to(pricing_path)
    expect(flash[:notice]).to eq(I18n.t("exams.denied.daily_limit_reached", limit: 1))
    expect(exam.reload).to be_status_in_progress
  end

  it "does not start a new exam once the allowance is spent" do
    post exams_path, params: { mode: "quick_quiz" }
    answer_first_question(Exam.last)

    expect { post exams_path, params: { mode: "quick_quiz" } }.not_to change(Exam, :count)
    expect(response).to redirect_to(pricing_path)
  end

  it "lets a student with a paid window keep going" do
    create(:entitlement, user: student)
    post exams_path, params: { mode: "quick_quiz" }
    answer_first_question(Exam.last)

    expect { post exams_path, params: { mode: "quick_quiz" } }.to change(Exam, :count).by(1)
  end

  it "records that the allowance was reached" do
    allow(Analytics).to receive(:capture)
    post exams_path, params: { mode: "quick_quiz" }
    answer_first_question(Exam.last)

    post exams_path, params: { mode: "quick_quiz" }

    expect(Analytics).to have_received(:capture).with(student, "daily_limit_reached")
  end
end

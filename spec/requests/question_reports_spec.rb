require "rails_helper"

RSpec.describe "Sugerir cambios", type: :request do
  let(:student) { create(:user) }
  let!(:kase) { create(:published_case, questions_count: 2) }

  def sign_in(user = student)
    post session_path, params: { email: user.email, password: "contrasena-segura" }
  end

  def start(mode = "quick_quiz")
    post exams_path, params: { mode: mode }
    Exam.last
  end

  def answer(exam, position, text = "Troponina I")
    exam_question = exam.exam_questions.find_by!(position: position)
    post exam_question_answer_path(exam, position),
      params: { answer_option_id: exam_question.question.answer_options.find_by!(text: text).id }
  end

  def suggest(exam, position, reason: "incorrect_answer", comment: "La guía dice otra cosa.")
    post exam_question_report_path(exam, position), params: { question_report: { reason: reason, comment: comment } }
  end

  before { sign_in }

  describe "one question at a time" do
    let(:exam) { start }

    it "is offered under the explanation once the answer is shown, and not before" do
      get exam_question_path(exam, 1)
      expect(response.body).not_to include(I18n.t("question_reports.panel.summary"))

      answer(exam, 1)
      get exam_question_path(exam, 1)

      expect(response.body).to include(I18n.t("question_reports.panel.summary"), "turbo-frame")
    end

    it "files the report in place and thanks the student" do
      answer(exam, 1)

      expect { suggest(exam, 1) }.to change(QuestionReport, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("turbo-frame", I18n.t("question_reports.panel.thanks"))
      expect(QuestionReport.last).to have_attributes(
        user: student, question: exam.exam_questions.first.question, reason: "incorrect_answer", status: "open"
      )
    end

    it "keeps one open report per question and says it is being reviewed" do
      answer(exam, 1)
      suggest(exam, 1)

      expect { suggest(exam, 1, reason: "typo") }.not_to change(QuestionReport, :count)
      expect(response.body).to include(I18n.t("question_reports.panel.pending"))

      get exam_question_path(exam, 1)
      expect(response.body).to include(I18n.t("question_reports.panel.pending"))
      expect(response.body).not_to include(I18n.t("question_reports.panel.submit"))
    end

    it "asks again when the reason is missing, keeping the form open" do
      answer(exam, 1)

      expect { suggest(exam, 1, reason: "") }.not_to change(QuestionReport, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("question_reports.panel.errors.reason"), "<details")
    end

    it "asks what to change when the reason is other and nothing is said" do
      answer(exam, 1)

      suggest(exam, 1, reason: "other", comment: "")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("question_reports.panel.errors.comment_blank"))
    end

    it "says how long a comment may be" do
      answer(exam, 1)

      suggest(exam, 1, comment: "a" * (QuestionReport::COMMENT_LIMIT + 1))

      expect(response.body).to include(
        I18n.t("question_reports.panel.errors.comment_too_long", count: QuestionReport::COMMENT_LIMIT)
      )
    end

    it "refuses a report before the answer is shown" do
      suggest(exam, 1)

      expect(response).to have_http_status(:not_found)
      expect(QuestionReport.count).to eq(0)
    end

    it "treats a missing form as a missing reason" do
      answer(exam, 1)

      post exam_question_report_path(exam, 1)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "is a 404 on another student's exam" do
      other = start
      answer(other, 1)
      delete session_path
      sign_in(create(:user))

      suggest(other, 1)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "on the single page" do
    let(:exam) { start("full_exam") }

    it "waits until the exam is finished, then is offered in its review" do
      answer(exam, 1)
      suggest(exam, 1)
      expect(response).to have_http_status(:not_found)

      patch complete_exam_path(exam)
      get exam_question_path(exam, 2)
      expect(response.body).to include(I18n.t("question_reports.panel.summary"))

      suggest(exam, 2, reason: "typo", comment: "")
      expect(response.body).to include(I18n.t("question_reports.panel.thanks"))
    end
  end
end

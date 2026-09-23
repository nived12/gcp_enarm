require "rails_helper"

RSpec.describe "Admin suggestion triage", type: :request do
  let(:reviewer) { create(:user, role: "reviewer") }
  let(:kase) { create(:published_case) }
  let!(:report) do
    create(
      :question_report, question: kase.questions.first, reason: "incorrect_answer",
      comment: "La B no es la inicial."
    )
  end

  def sign_in(user)
    post session_path, params: { email: user.email, password: "contrasena-segura" }
  end

  before { sign_in(reviewer) }

  describe "GET /admin/question_reports" do
    it "lists the open ones with the student, the question and a way to the case" do
      get admin_question_reports_path

      expect(response.body).to include(
        "La B no es la inicial.", report.user.email, kase.questions.first.text.truncate(200),
        review_clinical_case_path(kase), I18n.t("admin.question_reports.resolve")
      )
    end

    it "leaves closed ones out by default and shows them, with who closed them, when asked" do
      closed = create(:question_report, comment: "Ya corregida.")
      closed.close(status: "resolved", note: "Se cambió la opción.", by: reviewer)

      get admin_question_reports_path
      expect(response.body).not_to include("Ya corregida.")

      get admin_question_reports_path(filter_status: "resolved")
      expect(response.body).to include("Ya corregida.", "Se cambió la opción.", reviewer.email)
      expect(response.body).not_to include("La B no es la inicial.")

      get admin_question_reports_path(filter_status: "all")
      expect(response.body).to include("Ya corregida.", "La B no es la inicial.")
    end

    it "names an account that no longer exists as such" do
      closed = create(:question_report, comment: "De una cuenta que se fue.")
      closed.close(status: "dismissed", note: nil, by: reviewer)
      closed.update_column(:resolved_by_id, nil)

      get admin_question_reports_path(filter_status: "dismissed")

      expect(response.body).to include(I18n.t("admin.question_reports.someone"))
    end

    it "narrows by reason and by case" do
      other = create(:question_report, reason: "typo", comment: "Errata en la viñeta.")

      get admin_question_reports_path(reason: "typo")
      expect(response.body).to include("Errata en la viñeta.")
      expect(response.body).not_to include("La B no es la inicial.")

      get admin_question_reports_path(case_id: kase.id)
      expect(response.body).to include("La B no es la inicial.", I18n.t("admin.question_reports.for_case", id: kase.id))
      expect(response.body).not_to include(other.comment)
    end

    it "says so when nothing matches" do
      get admin_question_reports_path(reason: "ambiguous")

      expect(response.body).to include(I18n.t("admin.question_reports.empty.title"))
    end

    it "pages a long list and keeps the filters on the page links" do
      create_list(:question_report, Admin::QuestionReportsController::PER_PAGE + 1, reason: "typo")

      get admin_question_reports_path(reason: "typo")

      expect(response.body).to include("page=2")
      expect(response.body).to include("reason=typo")
    end
  end

  describe "PATCH /admin/question_reports/:id" do
    it "resolves it with a note, recording the reviewer, and stays on the same list" do
      patch admin_question_report_path(report),
        params: { status: "resolved", resolution_note: "Opción corregida.", filter_status: "open",
reason: "incorrect_answer" }

      expect(report.reload).to have_attributes(
        status: "resolved", resolution_note: "Opción corregida.",
        resolved_by: reviewer
      )
      expect(response).to redirect_to(admin_question_reports_path(filter_status: "open", reason: "incorrect_answer"))
      expect(flash[:notice]).to eq(I18n.t("admin.question_reports.done.resolved"))
    end

    it "dismisses it" do
      patch admin_question_report_path(report), params: { status: "dismissed" }

      expect(report.reload).to be_status_dismissed
      expect(flash[:notice]).to eq(I18n.t("admin.question_reports.done.dismissed"))
    end

    it "refuses an outcome it does not know" do
      patch admin_question_report_path(report), params: { status: "open" }

      expect(report.reload).to be_status_open
      expect(flash[:alert]).to eq(I18n.t("admin.question_reports.not_closed"))
    end

    it "is a 404 to a student" do
      sign_in(create(:user))

      patch admin_question_report_path(report), params: { status: "dismissed" }

      expect(response).to have_http_status(:not_found)
      expect(report.reload).to be_status_open
    end
  end
end

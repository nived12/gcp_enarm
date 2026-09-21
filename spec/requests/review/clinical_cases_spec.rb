require "rails_helper"

RSpec.describe "Review::ClinicalCases", type: :request do
  let(:reviewer) { create(:user, role: "reviewer") }
  let!(:clinical_case) { create(:clinical_case) }

  def sign_in(user)
    post session_path, params: { email: user.email, password: "contrasena-segura" }
  end

  describe "GET /review/clinical_cases" do
    it "lists the generated cases for a reviewer" do
      sign_in(reviewer)

      get review_clinical_cases_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(clinical_case.stem.truncate(180))
    end

    it "lets an admin in too" do
      sign_in(create(:user, role: "admin"))

      get review_clinical_cases_path

      expect(response).to have_http_status(:ok)
    end

    it "turns a student away — a draft case is unverified medicine" do
      sign_in(create(:user, role: "student"))

      get review_clinical_cases_path

      expect(response).to redirect_to(root_path)
    end

    it "turns away anyone not signed in" do
      get review_clinical_cases_path

      expect(response).to have_http_status(:redirect)
    end

    it "says so plainly when there is nothing to review yet" do
      ClinicalCase.delete_all
      sign_in(reviewer)

      get review_clinical_cases_path

      expect(response.body).to include(I18n.t("review.index.empty.title"))
    end

    it "narrows to one generation run when asked" do
      run = create(:generation_run)
      mine = create(:clinical_case, generation_run: run, stem: "Caso de la corrida elegida.")
      sign_in(reviewer)

      get review_clinical_cases_path(run_id: run.id)

      expect(response.body).to include(mine.stem)
      expect(response.body).not_to include(clinical_case.stem.truncate(180))
    end
  end

  describe "GET /review/clinical_cases/:id" do
    it "shows the options, the citation and the quoted span inside the recommendation" do
      recommendation = create(:recommendation, text: "Se recomienda realizar electrocardiograma de 12 derivaciones.")
      question = create(
        :question, clinical_case: clinical_case, recommendation: recommendation,
        source_quote: "electrocardiograma de 12 derivaciones"
      )
      create(:answer_option, question: question, position: 1, text: "Correcta", correct: true)
      sign_in(reviewer)

      get review_clinical_case_path(clinical_case)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Correcta")
      expect(response.body).to include("<mark>electrocardiograma de 12 derivaciones</mark>")
    end

    it "warns when the guideline behind the case is out of date" do
      old = create(:guideline, year: 2010)
      stale = create(:clinical_case, guideline: old)
      sign_in(reviewer)

      get review_clinical_case_path(stale)

      expect(response.body).to include(I18n.t("review.show.expired_warning"))
    end
  end
end

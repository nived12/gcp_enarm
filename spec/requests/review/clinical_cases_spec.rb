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

    it "pages rather than dumping every case on one screen" do
      create_list(:clinical_case, Review::ClinicalCasesController::PER_PAGE + 3)
      sign_in(reviewer)

      get review_clinical_cases_path

      expect(response.body).to include(I18n.t("review.pagination.next"))
      expect(response.body).to include(I18n.t("review.pagination.page", page: 1, total: 2))
    end

    it "serves the second page" do
      create_list(:clinical_case, Review::ClinicalCasesController::PER_PAGE + 3)
      sign_in(reviewer)

      get review_clinical_cases_path(page: 2)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("review.pagination.previous"))
    end

    it "marks the cases that carry a figure, so a reviewer can find them" do
      clinical_case.update!(clinical_image: create(:clinical_image, :stored, label: "CUADRO 2"))
      sign_in(reviewer)

      get review_clinical_cases_path

      expect(response.body).to include(I18n.t("review.index.figure_flag", label: "CUADRO 2"))
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

  describe "the second opinion" do
    let!(:disputed) do
      create(
        :clinical_case, verification_verdict: "unsupported", stem: "Caso que el verificador disputó.",
        verification_notes: "2. La recomendación indica otra conducta."
      )
    end

    before { clinical_case.update!(verification_verdict: "supported") }

    it "shows each case's verdict in words on the list" do
      sign_in(reviewer)

      get review_clinical_cases_path

      expect(response.body).to include(I18n.t("review.verdicts.supported"), I18n.t("review.verdicts.unsupported"))
    end

    it "narrows to one verdict, counting every verdict in the run" do
      create(:clinical_case, stem: "Caso sin verificar.")
      sign_in(reviewer)

      get review_clinical_cases_path(verdict: "unsupported")

      expect(response.body).to include(disputed.stem)
      expect(response.body).not_to include(clinical_case.stem.truncate(180))
      expect(response.body).to include("#{I18n.t("review.verdicts.unverified")} · 1")
      expect(response.body).to include(I18n.t("review.index.all", count: 3))
    end

    it "finds the cases the verifier has not read yet" do
      unread = create(:clinical_case, stem: "Caso sin verificar.")
      sign_in(reviewer)

      get review_clinical_cases_path(verdict: "unverified")

      expect(response.body).to include(unread.stem)
      expect(response.body).not_to include(disputed.stem)
    end

    it "ignores a verdict it does not know rather than showing nothing" do
      sign_in(reviewer)

      get review_clinical_cases_path(verdict: "inventado")

      expect(response.body).to include(disputed.stem, clinical_case.stem.truncate(180))
    end

    it "says so when a filter holds no cases, without claiming nothing was generated" do
      sign_in(reviewer)

      get review_clinical_cases_path(verdict: "ambiguous")

      expect(response.body).to include(I18n.t("review.index.empty_filter.title"))
      expect(response.body).not_to include(I18n.t("review.index.empty.title"))
    end

    it "explains the verdict on the case and lists the verifier's notes" do
      sign_in(reviewer)

      get review_clinical_case_path(disputed)

      expect(response.body).to include(I18n.t("review.show.second_opinion"))
      expect(response.body).to include(I18n.t("review.show.verdict_meaning.unsupported"))
      expect(response.body).to include("2. La recomendación indica otra conducta.")
    end

    # Page two of a filtered list, the next case and the way back all used to drop the
    # filter and wander into cases the reviewer had not asked for.
    it "keeps the filter on every link out of a filtered screen" do
      run = create(:generation_run)
      create_list(
        :clinical_case, Review::ClinicalCasesController::PER_PAGE + 1,
        generation_run: run, verification_verdict: "ambiguous"
      )
      sign_in(reviewer)

      get review_clinical_cases_path(run_id: run.id, verdict: "ambiguous")
      page_two = review_clinical_cases_path(run_id: run.id, verdict: "ambiguous", page: 2)
      expect(response.body).to include(ERB::Util.h(page_two))

      shown = run.clinical_cases.order(created_at: :desc, id: :desc).first
      get review_clinical_case_path(shown, run_id: run.id, verdict: "ambiguous")
      filtered = ERB::Util.h(review_clinical_cases_path(run_id: run.id, verdict: "ambiguous"))
      expect(response.body).to include(%(href="#{filtered}"))
      expect(response.body).to match(%r{href="/review/clinical_cases/\d+\?run_id=#{run.id}&amp;verdict=ambiguous"})
    end
  end

  describe "moving through the batch" do
    it "offers the next case so a reviewer does not go back to the list each time" do
      older = create(:clinical_case, created_at: 1.hour.ago, stem: "Caso anterior.")
      sign_in(reviewer)

      get review_clinical_case_path(clinical_case)

      expect(response.body).to include(review_clinical_case_path(older))
      expect(response.body).to include(I18n.t("review.show.next"))
    end

    it "offers the previous case from the second one on" do
      newer = create(:clinical_case, created_at: 1.hour.from_now, stem: "Caso posterior.")
      sign_in(reviewer)

      get review_clinical_case_path(clinical_case)

      expect(response.body).to include(review_clinical_case_path(newer))
      expect(response.body).to include(I18n.t("review.show.previous"))
    end

    it "says where in the batch a case sits" do
      create(:clinical_case, created_at: 1.hour.from_now)
      sign_in(reviewer)

      get review_clinical_case_path(clinical_case)

      expect(response.body).to include(I18n.t("review.show.position", position: 2, total: 2))
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

    it "links out to the guideline, naming the section the site's own menu uses" do
      guideline = create(
        :guideline, source: "live_site",
        document_url: "https://gpc.salud.gob.mx/X?DocumentoID=42"
      )
      section = create(
        :guideline_section, guideline: guideline, kind: "key_recommendation",
        heading: "RECOMENDACIONES CLAVE"
      )
      recommendation = create(
        :recommendation, guideline_section: section,
        text: "Se recomienda realizar electrocardiograma."
      )
      cited = create(:clinical_case, guideline: guideline)
      create(
        :question, clinical_case: cited, recommendation: recommendation,
        source_quote: "realizar electrocardiograma"
      )
      sign_in(reviewer)

      get review_clinical_case_path(cited)

      expect(response.body).to include("https://gpc.salud.gob.mx/X?DocumentoID=42")
      expect(response.body).to include("RECOMENDACIONES CLAVE")
    end

    it "shows the figure the case was written around, with its attribution" do
      image = create(
        :clinical_image, :stored, label: "CUADRO 2",
        caption: "MARCADORES DE CONGESTIÓN", attribution: "GPC SS-219-24 · 2024"
      )
      clinical_case.update!(clinical_image: image)
      sign_in(reviewer)

      get review_clinical_case_path(clinical_case)

      expect(response.body).to include("CUADRO 2")
      expect(response.body).to include("MARCADORES DE CONGESTIÓN")
      # The licence asks for it, so it is on the page and not only in the database.
      expect(response.body).to include("GPC SS-219-24 · 2024")
    end

    # Guideline figures are drawn for a printed page and are unreadable at phone width.
    it "opens the figure full size, where it can be zoomed" do
      clinical_case.update!(clinical_image: create(:clinical_image, :stored))
      sign_in(reviewer)

      get review_clinical_case_path(clinical_case)

      expect(response.body).to include(I18n.t("review.show.open_figure"))
      expect(response.body).to match(%r{href="[^"]*/rails/active_storage/blobs/[^"]*cuadro_2\.png"})
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

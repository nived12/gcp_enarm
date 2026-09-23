require "rails_helper"

RSpec.describe "Admin access", type: :request do
  def sign_in(user)
    post session_path, params: { email: user.email, password: "contrasena-segura" }
  end

  staff_pages = %i[admin_root_path admin_clinical_cases_path admin_question_reports_path]
  admin_pages = %i[admin_costs_path admin_ingestion_path admin_users_path]

  it "sends anyone not signed in to sign in" do
    get admin_root_path

    expect(response).to redirect_to(new_session_path)
  end

  (staff_pages + admin_pages).each do |page|
    it "is a plain 404 to a student at #{page}, so the admin surface is not advertised" do
      sign_in(create(:user))

      get public_send(page)

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(I18n.t("admin.eyebrow"))
    end

    it "opens #{page} to an admin" do
      sign_in(create(:user, :admin))

      get public_send(page)

      expect(response).to have_http_status(:ok)
    end
  end

  staff_pages.each do |page|
    it "opens #{page} to a reviewer" do
      sign_in(create(:user, role: "reviewer"))

      get public_send(page)

      expect(response).to have_http_status(:ok)
    end
  end

  admin_pages.each do |page|
    it "keeps #{page} from a reviewer" do
      sign_in(create(:user, role: "reviewer"))

      get public_send(page)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the overview" do
    before do
      create(:question_report)
      create(:clinical_case, verification_verdict: "ambiguous")
      create(:generation_run, cost_usd: 0.25)
    end

    it "counts the open suggestions and the queue, and shows the spend to an admin" do
      sign_in(create(:user, :admin))

      get admin_root_path

      expect(response.body).to include(I18n.t("admin.dashboard.open_reports", count: 1), "US$0.2500")
      expect(response.body).to include(I18n.t("admin.nav.users"))
    end

    it "leaves the money and the admin-only sections out for a reviewer" do
      sign_in(create(:user, role: "reviewer"))

      get admin_root_path

      expect(response.body).to include(I18n.t("admin.dashboard.queue", count: 2))
      expect(response.body).not_to include("US$", I18n.t("admin.nav.users"))
    end
  end
end

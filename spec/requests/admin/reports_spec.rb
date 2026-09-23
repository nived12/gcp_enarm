require "rails_helper"

# The two read-only screens: what the LLM work cost, and what the corpus holds.
RSpec.describe "Admin costs and ingestion", type: :request do
  before { post session_path, params: { email: create(:user, :admin).email, password: "contrasena-segura" } }

  describe "GET /admin/costs" do
    it "totals runs, tokens and dollars per purpose, provider and model" do
      create(
        :generation_run, purpose: "generation", provider: "gemini", model: "gemini-3.1-flash-lite",
        input_tokens: 1_000, output_tokens: 500, cost_usd: 0.20
      )
      create(
        :generation_run, purpose: "generation", provider: "gemini", model: "gemini-3.1-flash-lite",
        input_tokens: 2_000, output_tokens: 500, cost_usd: 0.05
      )
      create(
        :generation_run, purpose: "verification", provider: "deepseek", model: "deepseek-flash",
        input_tokens: 100, output_tokens: 100, cost_usd: 0.0125
      )

      get admin_costs_path

      expect(response.body).to include(
        "US$0.2500", "US$0.0125", "US$0.2625", "3,000", "deepseek · deepseek-flash",
        I18n.t("admin.costs.purposes.verification"), I18n.t("admin.costs.total_detail", runs: 3, tokens: "4,200")
      )
      expect(response.body).to include("width: 100.0%", "width: 5.0%")
    end

    it "says so when nothing has run yet" do
      get admin_costs_path

      expect(response.body).to include(I18n.t("admin.costs.empty.title"))
    end
  end

  describe "GET /admin/ingestion" do
    it "counts guidelines by source and by whether they yielded statements, and cases by specialty" do
      cited = create(:recommendation).guideline_section.guideline
      create(:guideline, source: "web_archive", year: 2010)
      create(:guideline, year: nil)
      specialty = create(:specialty, name: "Pediatría")
      create(:published_case, specialty: specialty, guideline: cited)
      create(:clinical_case, specialty: specialty)
      create(:clinical_case)

      get admin_ingestion_path

      body = response.body
      expect(body).to include(I18n.t("admin.ingestion.with_statements", count: 1, total: 2))
      expect(body).to include(I18n.t("admin.ingestion.with_statements", count: 0, total: 1))
      expect(body).to include("Pediatría", I18n.t("admin.ingestion.unfiled"))
    end

    it "leaves out the unfiled row when every case has a specialty" do
      get admin_ingestion_path

      expect(response.body).not_to include(I18n.t("admin.ingestion.unfiled"))
      expect(response.body).to include(I18n.t("admin.ingestion.with_statements", count: 0, total: 0))
    end
  end
end

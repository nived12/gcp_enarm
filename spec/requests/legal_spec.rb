require "rails_helper"

RSpec.describe "Legal pages", type: :request do
  LegalPage::NAMES.each do |name|
    it "shows the #{name} draft to anyone, marked as awaiting review" do
      get legal_path(name)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("legal.titles.#{name}"), I18n.t("legal.draft_notice"))
    end
  end

  it "has no page for anything else" do
    get "/legal/secret"

    expect(response).to have_http_status(:not_found)
  end

  it "links every legal page from the footer" do
    get root_path

    LegalPage::NAMES.each { |name| expect(response.body).to include(legal_path(name)) }
    expect(response.body).to include(pricing_path)
  end
end

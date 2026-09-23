require "rails_helper"

RSpec.describe "Landing page", type: :request do
  it "tells a visitor why the questions are different and what they cost" do
    get root_path

    expect(response.body).to include(
      I18n.t("landing.different.citation.title"),
      I18n.t("landing.different.currency.title")
    )
    expect(response.body).to include(I18n.t("landing.price.title", amount: "$92"), pricing_path)
  end

  it "keeps prices off a signed-in student's home screen" do
    user = create(:user)
    post session_path, params: { email: user.email, password: "contrasena-segura" }

    get root_path

    expect(response.body).not_to include(I18n.t("landing.price.body"))
    expect(response.body).to include(account_path)
  end
end

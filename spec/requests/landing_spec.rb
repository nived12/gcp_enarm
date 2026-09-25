require "rails_helper"

RSpec.describe "Landing page", type: :request do
  it "lets a visitor answer a real case and see the recommendation behind each answer" do
    kase = create(:published_case)
    create(:published_case)

    get root_path(caso: kase.export_key)

    question = kase.questions.first
    expect(response.body).to include(kase.stem, question.text, "<mark>electrocardiograma de 12 derivaciones</mark>")
    expect(response.body).to include(%(data-correct="true"), "caso=")
    expect(response.body).to include(I18n.t("landing.numbers.title"), I18n.t("landing.numbers.questions.label"))
  end

  it "still renders when the bank has no case to show" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(%(id="caso"), I18n.t("landing.numbers.title"))
    expect(response.body).to include(I18n.t("landing.anatomy.title"))
  end

  it "prices every access window per day, with the free allowance" do
    get root_path

    expect(response.body).to include(
      I18n.t("landing.pricing.per_day", amount: "$3"), I18n.t("landing.pricing.per_day", amount: "$7"),
      I18n.t(
        "landing.pricing.free", limit: SubscriptionAccess.free_daily_questions,
        trial_days: SubscriptionAccess.trial_days
      ),
      pricing_path
    )
  end

  it "tells who made it and answers the doubts that stop a sign-up" do
    get root_path

    expect(response.body).to include(I18n.t("landing.doctor.title"), I18n.t("landing.faq.items.trial.question"),
                                         I18n.t("landing.faq.items.oxxo.question"))
    expect(response.body).to include(I18n.t("landing.hero.reassurance", trial_days: SubscriptionAccess.trial_days))
  end

  it "is laid out wide, with its own title and a canonical on the launch domain" do
    get root_path

    expect(response.body).to include("max-w-6xl", "<title>#{I18n.t("landing.meta.title")}</title>")
    expect(response.body).to include(%(<link rel="canonical" href="https://gpcenarm.com/">))
  end

  it "serves its fonts itself and preloads the face the headline is set in" do
    get root_path

    expect(response.body).not_to include("fonts.googleapis.com", "fonts.gstatic.com")
    expect(response.body).to include(
      %(<link rel="preload" href="#{ActionController::Base.helpers.asset_path("alan-sans-latin.woff2")}" as="font")
    )
  end

  it "keeps the app's reading width and the sign-up button off the sign-up page" do
    get new_registration_path

    expect(response.body).to include("max-w-3xl")
    expect(response.body).not_to include("max-w-6xl", new_registration_path(from: "header"))
  end

  it "keeps prices off a signed-in student's home screen" do
    user = create(:user)
    post session_path, params: { email: user.email, password: "contrasena-segura" }

    get root_path

    expect(response.body).not_to include(I18n.t("landing.pricing.title"))
    expect(response.body).to include(account_path)
  end
end

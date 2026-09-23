require "rails_helper"

# A visitor who picks a plan on /pricing must sign up (or in) before paying, and should
# land back on that plan afterwards rather than on the home screen.
RSpec.describe "Returning to pricing after signing up", type: :request do
  let(:chosen) { pricing_path(plan: "six_months", anchor: "plan-six_months") }

  def sign_up
    post registration_path, params: {
      user: { first_name: "Dana", last_name: "Ríos", email: "nueva@example.com", password: "contrasena-segura",
              password_confirmation: "contrasena-segura" }
    }
  end

  def sign_in(user)
    post session_path, params: { email: user.email, password: "contrasena-segura" }
  end

  it "links each plan's sign-up button back to that plan", :stripe do
    get pricing_path

    expect(response.body).to include(CGI.escapeHTML(new_registration_path(return_to: chosen)))
  end

  it "sends a new account back to the chosen plan" do
    get new_registration_path(return_to: chosen)
    sign_up

    expect(response).to redirect_to("http://www.example.com#{chosen}")
    expect(flash[:notice]).to eq(I18n.t("registrations.create.welcome"))
  end

  it "keeps the way back when the visitor switches to signing in" do
    user = create(:user)
    get new_registration_path(return_to: chosen)
    get new_session_path

    sign_in(user)

    expect(response).to redirect_to("http://www.example.com#{chosen}")
  end

  it "accepts the way back on the sign-in page too" do
    user = create(:user)
    get new_session_path(return_to: chosen)

    sign_in(user)

    expect(response).to redirect_to("http://www.example.com#{chosen}")
  end

  it "uses the way back once" do
    get new_registration_path(return_to: chosen)
    sign_up
    delete session_path

    sign_in(User.find_by!(email: "nueva@example.com"))

    expect(response).to redirect_to(root_url)
  end

  it "still sends a plain sign-up home" do
    get new_registration_path
    sign_up

    expect(response).to redirect_to(root_url)
  end

  [
    "https://evil.example/phish", "//evil.example/phish", "///evil.example", "/\\evil.example",
    "javascript:alert(1)", "/\t/evil.example", ""
  ].each do |unsafe|
    it "ignores #{unsafe.inspect} as a way back" do
      get new_registration_path(return_to: unsafe)
      sign_up

      expect(response).to redirect_to(root_url)
    end
  end

  it "ignores a way back that is not a string" do
    get new_session_path, params: { return_to: { host: "evil.example" } }
    sign_in(create(:user))

    expect(response).to redirect_to(root_url)
  end

  it "accepts a full URL on this site" do
    get new_registration_path(return_to: "http://www.example.com/pricing")
    sign_up

    expect(response).to redirect_to("http://www.example.com/pricing")
  end

  describe "the pricing page it returns to", :stripe do
    it "highlights the chosen plan in place of the best value" do
      sign_in(create(:user))

      get pricing_path(plan: "six_months")

      page = Nokogiri::HTML(response.body)
      expect(page.css("li[data-chosen]").map { |node| node["data-plan"] }).to eq([ "six_months" ])
      expect(page.at_css("#plan-six_months")["class"]).to include("ring-accent")
      expect(page.at_css("#plan-twelve_months")["class"]).not_to include("ring-accent")
      expect(page.at_css("#plan-six_months .btn")["class"]).to include("btn--primary")
    end

    it "keeps the best value highlighted for an unknown plan" do
      get pricing_path(plan: "lifetime")

      page = Nokogiri::HTML(response.body)
      expect(page.css("li[data-chosen]")).to be_empty
      expect(page.at_css("#plan-twelve_months")["class"]).to include("ring-accent")
    end
  end
end

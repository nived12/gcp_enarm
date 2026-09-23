require "rails_helper"

RSpec.describe "Sessions", type: :request do
  let!(:user) { create(:user, email: "gabriela@example.com", password: "contrasena-segura") }

  def sign_in
    post session_path, params: { email: "gabriela@example.com", password: "contrasena-segura" }
  end

  describe "GET / when signed in" do
    it "renders the dashboard rather than the landing page" do
      sign_in
      get root_path

      expect(response.body).to include(I18n.t("home.dashboard.greeting", name: user.first_name))
    end
  end

  describe "DELETE /session" do
    it "signs the user out and drops the session row" do
      sign_in

      expect { delete session_path }.to change(Session, :count).by(-1)

      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq(I18n.t("sessions.destroy.success"))
    end
  end

  describe "requesting a protected page while signed out" do
    # There is no authenticated-only page yet, so drive the concern directly: it is
    # what every Phase 3 exam route will depend on.
    it "remembers where the visitor was headed and returns them after signing in" do
      with_protected_route do
        get "/protected"
        expect(response).to redirect_to(new_session_path)

        sign_in
        expect(response).to redirect_to("http://www.example.com/protected")
      end
    end
  end

  def with_protected_route
    stub_const(
      "ProtectedController", Class.new(ApplicationController) do
                               def show = render(plain: "secreto")
                             end
    )

    Rails.application.routes.draw do
      resource :session
      resource :registration, only: %i[new create]
      resources :passwords, param: :token
      get "protected" => "protected#show"
      root "home#show"
    end

    yield
  ensure
    Rails.application.reload_routes!
  end
end

require "rails_helper"

RSpec.describe "Authentication", type: :request do
  describe "GET /" do
    it "renders the landing page for a visitor" do
      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Cada pregunta")
    end
  end

  describe "GET /session/new" do
    it "renders the sign-in form" do
      get new_session_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Correo electrónico")
    end
  end

  describe "GET /registration/new" do
    it "renders the sign-up form" do
      get new_registration_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /passwords/new" do
    it "renders the password reset request form" do
      get new_password_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /registration" do
    it "creates the account and signs the user in" do
      expect {
        post registration_path, params: {
          user: { first_name: "Gabriela", last_name: "Guadarrama", email: "nueva@example.com",
                  password: "contrasena-segura", password_confirmation: "contrasena-segura" }
        }
      }.to change(User, :count).by(1)

      expect(response).to redirect_to(root_path)
    end

    it "keeps the time zone the browser reported, and the default for one tzinfo does not know" do
      sign_up = lambda do |email, zone|
        post registration_path, params: {
          user: { first_name: "Dana", last_name: "Ríos", email: email, password: "contrasena-segura",
                  password_confirmation: "contrasena-segura",
                  time_zone: zone }.compact
        }
        User.find_by!(email: email).time_zone
      end

      expect(sign_up.call("tijuana@example.com", "America/Tijuana")).to eq("America/Tijuana")
      expect(sign_up.call("marte@example.com", "Mars/Olympus_Mons")).to eq("America/Mexico_City")
      expect(sign_up.call("vacio@example.com", "")).to eq("America/Mexico_City")
      expect(sign_up.call("sin-dato@example.com", nil)).to eq("America/Mexico_City")
    end

    it "asks for surnames as well as given names" do
      post registration_path, params: {
        user: { first_name: "Dana", last_name: "", email: "nueva@example.com",
                password: "contrasena-segura", password_confirmation: "contrasena-segura" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Apellidos no puede estar en blanco", "value=\"Dana\"")
    end

    it "re-renders the form when the passwords do not match" do
      post registration_path, params: {
        user: { email: "nueva@example.com",
                password: "contrasena-segura", password_confirmation: "otra-cosa" }
      }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /session" do
    let!(:user) { create(:user, email: "gabriela@example.com", password: "contrasena-segura") }

    it "signs in with valid credentials" do
      post session_path, params: { email: "gabriela@example.com", password: "contrasena-segura" }

      expect(response).to redirect_to(root_path)
    end

    it "rejects a wrong password" do
      post session_path, params: { email: "gabriela@example.com", password: "incorrecta" }

      expect(response).to redirect_to(new_session_path)
      expect(flash[:alert]).to eq(I18n.t("sessions.create.invalid"))
    end
  end
end

require "rails_helper"

RSpec.describe "Password resets", type: :request do
  let!(:user) { create(:user, email: "gabriela@example.com", password: "contrasena-segura") }

  describe "POST /passwords" do
    it "sends the reset mail to a known address" do
      expect {
        post passwords_path, params: { email: "gabriela@example.com" }
      }.to have_enqueued_mail(PasswordsMailer, :reset)

      expect(response).to redirect_to(new_session_path)
      expect(flash[:notice]).to eq(I18n.t("passwords.create.sent"))
    end

    # The response must not differ for an unknown address, or the form becomes an
    # account-enumeration oracle.
    it "gives an unknown address the identical response, and sends nothing" do
      expect {
        post passwords_path, params: { email: "desconocida@example.com" }
      }.not_to have_enqueued_mail(PasswordsMailer, :reset)

      expect(response).to redirect_to(new_session_path)
      expect(flash[:notice]).to eq(I18n.t("passwords.create.sent"))
    end
  end

  describe "GET /passwords/:token/edit" do
    it "renders the new-password form for a valid token" do
      get edit_password_path(user.password_reset_token)

      expect(response).to have_http_status(:ok)
    end

    it "sends an expired token back to the request form" do
      token = user.password_reset_token

      travel 16.minutes do
        get edit_password_path(token)
      end

      expect(response).to redirect_to(new_password_path)
      expect(flash[:alert]).to eq(I18n.t("passwords.update.invalid_token"))
    end
  end

  describe "PATCH /passwords/:token" do
    it "sets the new password and signs every existing session out" do
      create(:session, user: user)

      patch password_path(user.password_reset_token),
        params: { password: "nueva-contrasena", password_confirmation: "nueva-contrasena" }

      expect(response).to redirect_to(new_session_path)
      expect(user.sessions.reload).to be_empty
      expect(user.reload.authenticate("nueva-contrasena")).to be_truthy
    end

    it "sends the user back when the confirmation does not match" do
      token = user.password_reset_token

      patch password_path(token), params: { password: "nueva-contrasena", password_confirmation: "otra" }

      expect(response).to redirect_to(edit_password_path(token))
      expect(flash[:alert]).to be_present
      expect(user.reload.authenticate("contrasena-segura")).to be_truthy
    end
  end
end

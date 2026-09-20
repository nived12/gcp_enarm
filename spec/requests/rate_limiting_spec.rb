require "rails_helper"

# Rate limiting is the only brute-force control on three unauthenticated forms.
# It needs a real cache store, which config/environments/test.rb gives Action
# Controller specifically; rails_helper clears it between examples.
RSpec.describe "Rate limiting", type: :request do
  it "throttles repeated sign-in attempts" do
    11.times do
      post session_path, params: { email: "gabriela@example.com", password: "incorrecta" }
    end

    expect(response).to redirect_to(new_session_path)
    expect(flash[:alert]).to eq(I18n.t("sessions.create.rate_limited"))
  end

  it "throttles repeated password reset requests" do
    11.times { post passwords_path, params: { email: "gabriela@example.com" } }

    expect(response).to redirect_to(new_password_path)
    expect(flash[:alert]).to eq(I18n.t("sessions.create.rate_limited"))
  end

  it "throttles repeated sign-up attempts" do
    11.times do |n|
      post registration_path, params: {
        user: { email: "nueva#{n}@example.com",
                password: "contrasena-segura", password_confirmation: "contrasena-segura" }
      }
    end

    expect(response).to redirect_to(new_registration_path)
    expect(flash[:alert]).to eq(I18n.t("sessions.create.rate_limited"))
  end
end

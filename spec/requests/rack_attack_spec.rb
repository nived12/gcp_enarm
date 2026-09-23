require "rails_helper"

# Rack::Attack counts in Rails.cache, which is a :null_store under test, so its rules
# are inert everywhere except here, where each example gets a real store of its own.
RSpec.describe "Rack::Attack", type: :request do
  around do |example|
    previous = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rack::Attack.cache.store = previous
  end

  it "throttles guesses at one account from many addresses" do
    11.times do |n|
      post session_path, params: { email: "Gabriela@Example.com ", password: "incorrecta" },
        headers: { "REMOTE_ADDR" => "10.0.0.#{n}" }
    end

    expect(response).to have_http_status(:too_many_requests)
    expect(response.body).to eq(I18n.t("sessions.create.rate_limited"))
    expect(response.headers["retry-after"]).to eq("60")
  end

  it "throttles sign-ups from one address" do
    ActionController::Base.cache_store.clear
    21.times do |n|
      ActionController::Base.cache_store.clear
      post registration_path,
        params: { user: { email: "nueva#{n}@example.com", password: "x", password_confirmation: "y" } }
    end

    expect(response).to have_http_status(:too_many_requests)
  end

  it "throttles password reset requests for one address" do
    6.times do |n|
      post passwords_path, params: { email: "gabriela@example.com" }, headers: { "REMOTE_ADDR" => "10.1.0.#{n}" }
    end

    expect(response).to have_http_status(:too_many_requests)
  end

  it "throttles one address hammering the app" do
    301.times { get legal_path("terms") }

    expect(response).to have_http_status(:too_many_requests)
  end

  it "never throttles Stripe's webhooks or the health check" do
    310.times { post stripe_webhook_path, params: "{}", headers: { "CONTENT_TYPE" => "application/json" } }
    expect(response).to have_http_status(:bad_request)

    get rails_health_check_path
    expect(response).to have_http_status(:ok)
  end
end

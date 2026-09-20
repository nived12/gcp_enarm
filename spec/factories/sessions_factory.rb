FactoryBot.define do
  factory :session do
    user
    user_agent { "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)" }
    ip_address { "187.190.0.1" }
  end
end

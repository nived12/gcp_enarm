FactoryBot.define do
  factory :user do
    sequence(:email_address) { |n| "medico#{n}@example.com" }
    password { "contrasena-segura" }
    name { "Gabriela" }
    locale { "es" }
    role { "student" }

    trait :admin do
      role { "admin" }
    end

    trait :granted_premium do
      granted_premium_until { 1.year.from_now }
    end

    trait :trial_expired do
      after(:create) { |user| user.update_column(:trial_ends_at, 1.day.ago) }
    end
  end
end

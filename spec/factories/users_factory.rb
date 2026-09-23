FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "medico#{n}@example.com" }
    password { "contrasena-segura" }
    first_name { "Gabriela" }
    last_name { "Guadarrama López" }
    locale { "es" }
    role { "student" }
    email_verified_at { Time.current }

    trait :unverified do
      email_verified_at { nil }
    end

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

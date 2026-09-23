FactoryBot.define do
  factory :review_card do
    user
    due_on { Date.current }

    trait :case do
      clinical_case factory: :published_case
    end

    trait :pearl do
      recommendation
    end
  end
end

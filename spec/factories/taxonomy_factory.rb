FactoryBot.define do
  factory :specialty do
    sequence(:name) { |n| "Medicina Interna #{n}" }
    slug { name.to_s.parameterize.presence }
    kind { "core" }
    color_token { "indigo" }
    sequence(:position)
  end

  factory :branch do
    specialty
    sequence(:name) { |n| "Cardiología #{n}" }
    slug { name.to_s.parameterize.presence }
    sequence(:position)
  end

  factory :topic do
    branch
    sequence(:name) { |n| "Infarto agudo de miocardio #{n}" }
    slug { name.to_s.parameterize.presence }
    sequence(:position)
    aliases { [] }
  end

  factory :guideline_topic do
    guideline
    topic
    relevance { 0.5 }
  end
end

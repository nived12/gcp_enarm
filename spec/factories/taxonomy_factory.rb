FactoryBot.define do
  factory :specialty do
    sequence(:name) { |n| "Medicina Interna #{n}" }
    slug { name.to_s.parameterize.presence }
    kind { "core" }
    color_token { "indigo" }
    sequence(:position)
  end

  # The three contexts the convocatoria frames every case in, under the slugs a
  # generation prompt's setting codes resolve to. Found rather than duplicated, so a spec
  # can ask for Urgencias twice and get the same row.
  {
    emergency_setting: ["Urgencias", "urgencias", "red"],
    family_medicine_setting: ["Medicina Familiar", "medicina-familiar", "violet"],
    public_health_setting: ["Salud Pública", "salud-publica", "teal"]
  }.each do |factory_name, (name, slug, color)|
    factory factory_name, parent: :specialty do
      name { name }
      slug { slug }
      kind { "cross_cutting" }
      color_token { color }
      initialize_with { Specialty.find_or_initialize_by(slug: slug) }
    end
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

FactoryBot.define do
  factory :guideline_section do
    guideline
    sequence(:external_id) { |n| (36_770 + n).to_s }
    heading { "RECOMENDACIONES" }
    clinical_question { "EN POBLACIÓN MAYOR DE 18 AÑOS DE EDAD ¿SE SUGIERE LA VACUNACIÓN?" }
    kind { "recommendation" }
    sequence(:position)
    body { "<div class=\"separador\">A NICE Hong K, 2021</div><p>Se recomienda otorgar educación prenatal.</p>" }
    content_hash { Digest::SHA256.hexdigest(body) }
  end
end

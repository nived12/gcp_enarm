FactoryBot.define do
  factory :clinical_image do
    guideline_section
    label { "CUADRO 2" }
    caption { "MARCADORES CLÍNICOS DE CONGESTIÓN" }
    kind { "table" }
    sequence(:position)
    remote_path { "imagenes/doc_4081/cuadro_2.jpg" }
    attribution { "GPC SS-219-24 · Insuficiencia cardiaca aguda · 2024" }
    source { "gpc" }

    trait :stored do
      after(:build) do |image|
        image.file.attach(
          io: Rails.root.join("spec/fixtures/files/gpc/figure.png").open,
          filename: "cuadro_2.png", content_type: "image/png"
        )
      end
    end
  end
end

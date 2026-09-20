FactoryBot.define do
  factory :generation_run do
    purpose { "generation" }
    provider { "gemini" }
    model { "gemini-3.1-flash-lite" }
    status { "running" }
    started_at { Time.current }
  end

  factory :clinical_case do
    stem { "Paciente de 54 años acude por dolor torácico opresivo de dos horas de evolución." }
    locale { "es" }
    difficulty { "medium" }
    status { "draft" }
    source { "gpc_generated" }
  end

  factory :question do
    clinical_case
    sequence(:position) { |n| n }
    text { "¿Cuál es el estudio inicial indicado?" }
    explanation { "El electrocardiograma se realiza en los primeros diez minutos." }
  end

  factory :answer_option do
    question
    sequence(:position) { |n| n }
    text { "Electrocardiograma de 12 derivaciones" }
    correct { false }
  end
end

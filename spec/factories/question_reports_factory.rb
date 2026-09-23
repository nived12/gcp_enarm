FactoryBot.define do
  factory :question_report do
    user
    question
    reason { "incorrect_answer" }
    comment { "La opción marcada como correcta contradice la guía." }
  end
end

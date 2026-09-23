FactoryBot.define do
  factory :study_plan do
    user
    template { "every_day" }
    starts_on { Date.new(2026, 10, 5) }
    exam_date { starts_on + 60 }
  end

  factory :study_plan_day do
    study_plan
    sequence(:date) { |n| Date.new(2026, 10, 5) + n }
    kind { "topics" }
    pass_number { 1 }
  end
end

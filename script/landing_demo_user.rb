# Builds the account the landing page's screenshots are taken from: two weeks of quizzes
# with a realistic mix of right, wrong and guessed answers, a live streak, a study plan to
# the 2027 exam and a review queue. Run against a copy of the bank, never production:
#
#   DATABASE_URL=postgres:///gpc_enarm_preview bin/rails runner script/landing_demo_user.rb
#
# Then script/landing_screenshots.mjs signs in as this account. Running it again starts
# the account over.
abort "Refusing to run in production." if Rails.env.production?

EMAIL = "landing-demo@example.test".freeze
PASSWORD = "landing-demo-2026".freeze
random = Random.new(2027)

User.find_by(email: EMAIL)&.destroy!
user = User.create!(
  email: EMAIL, password: PASSWORD, first_name: "Andrea", last_name: "Ramírez Soto",
  email_verified_at: Time.current, granted_premium_until: 1.year.from_now,
  time_zone: "America/Mexico_City"
)

today = user.study_date

# Finished quizzes over the last two weeks, about seven in ten right, some guessed.
13.downto(1) do |days_ago|
  travel_to = (today - days_ago).in_time_zone(user.time_zone).change(hour: 21)
  exam = Exams::Builder.call(user: user, mode: "quick_quiz", random: random).payload[:exam]
  exam.exam_questions.includes(question: :answer_options).each do |exam_question|
    options = exam_question.question.answer_options.to_a
    correct = options.find(&:correct?)
    right = random.rand < 0.7
    chosen = right ? correct : (options - [correct]).sample(random: random)
    confidence = right ? %w[sure sure unsure
guess].sample(random: random) : %w[sure unsure guess].sample(random: random)
    Exams::AnswerRecorder.call(exam_question, answer_option_id: chosen.id, confidence: confidence)
  end
  exam.complete!
  exam.update_columns(started_at: travel_to, completed_at: travel_to + 12.minutes)
  Answer.joins(:exam_question).where(exam_questions: { exam_id: exam.id })
    .update_all(answered_at: travel_to + 6.minutes)
  StudyDay.find_or_initialize_by(user: user, date: today - days_ago)
    .update!(questions_answered: exam.question_count)
end
StudyDay.where(user: user, date: today).destroy_all

# A few cases due today, so the review screen shows a queue rather than its empty state.
ReviewCard.where(user: user).where.not(clinical_case_id: nil).order(:id).limit(6).update_all(due_on: today)

StudyPlans::Builder.call(user: user, exam_date: Date.new(2027, 9, 27), template: "six_days")

# One quiz left open on its first question, for the question screen, and a Simulacro.
quiz = Exams::Builder.call(user: user, mode: "quick_quiz", random: random).payload[:exam]
mock = Exams::Builder.call(user: user, mode: "full_exam", random: random).payload[:exam]
Rails.root.join("tmp/landing_demo.json").write(
  { email: EMAIL, password: PASSWORD, quiz_id: quiz.id, mock_id: mock.id }.to_json
)

puts "#{EMAIL} / #{PASSWORD}: #{user.exams.status_completed.count} quizzes, " \
     "#{ReviewCard.where(user: user).count} review cards, plan #{user.study_plan.present?}"

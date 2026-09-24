# Sitting a case in a spec without going through the simulator: each outcome is :right,
# :wrong, [:wrong, reason] or nil for a question left blank. Pass `exam:` to add the case
# to an exam already started; the review schedule follows through the models' callbacks.
module ReviewHelpers
  def sit(user, kase, outcomes, exam: nil, timing: "after_each", finish: false, option: nil, confidence: nil)
    exam ||= create(:exam, user: user, feedback_timing: timing, question_count: outcomes.size)
    offset = exam.exam_questions.count
    kase.questions.zip(outcomes).each.with_index(1) do |(question, outcome), index|
      exam_question = exam.exam_questions.create!(question: question, clinical_case: kase, position: offset + index)
      next if outcome.nil?

      right, reason = Array(outcome).then { |kind, why| [kind == :right, why] }
      chosen = option || question.answer_options.find { |candidate| candidate.correct? == right }
      exam_question.create_answer!(
        answer_option: chosen, correct: right, answered_at: Time.current,
        error_reason: reason, confidence: confidence
      )
    end
    exam.update!(question_count: exam.exam_questions.count)
    exam.complete! if finish
    exam
  end
end

RSpec.configure { |config| config.include ReviewHelpers }

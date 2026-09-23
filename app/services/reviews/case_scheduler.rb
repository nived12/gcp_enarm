# Keeps a student's review schedule for the clinical cases they have missed.
#
# The schedule is replayed from the answers every time one of them changes, rather than
# nudged forward one event at a time. A case is graded when its attempt is over, but the
# student's reason for a miss can arrive later (the triage is a tap after the
# explanation) or change, and an answer on the single page can change until the exam is
# finished. A replay gives the same schedule whichever order those arrive in.
#
# One attempt is one exam's questions about the case. Each attempt is one SM-2 review:
#
# * every question right: quality 4 — recalled, with the effort a case takes;
# * a miss the student put down to misreading the case or running out of time: quality 3.
#   That is a pass in SM-2 — the card keeps its progress but its ease drops — because
#   neither is a gap in what they know, and making them relearn it would be wrong;
# * a miss from confusing diagnoses: quality 2, a lapse;
# * a miss from not knowing: quality 1, a lapse that costs the most ease;
# * a miss they gave no reason for, or a blank: quality 2. Unknown is not "did not know";
#   it is the middle of the lapses rather than the bottom.
#
# With several misses in one attempt the worst one grades it. A case enters the deck at
# its first attempt with a miss; right answers before that are not reviews of anything.
# Discarded exams count: discarding takes a sitting out of the average, but the case was
# still read and still missed.
module Reviews
  class CaseScheduler < ApplicationService
    CORRECT_QUALITY = 4
    UNKNOWN_MISS_QUALITY = 2
    MISS_QUALITIES = {
      "misread_case" => 3, "ran_out_of_time" => 3, "confused_diagnoses" => 2, "did_not_know" => 1
    }.freeze

    Attempt = Data.define(:date, :exam_id, :quality, :missed)

    def initialize(user, clinical_case_ids)
      super()
      @user = user
      @clinical_case_ids = Array(clinical_case_ids).uniq
    end

    def call
      attempts = attempts_by_case
      cards = ReviewCard.where(user: user, clinical_case_id: clinical_case_ids).index_by(&:clinical_case_id)
      clinical_case_ids.each { |id| replay(cards[id], id, attempts.fetch(id, [])) }
      success
    end

    private

    attr_reader :user, :clinical_case_ids

    def replay(card, clinical_case_id, attempts)
      first_miss = attempts.index(&:missed)
      return card&.destroy! if first_miss.nil?

      card ||= ReviewCard.new(user: user, clinical_case_id: clinical_case_id)
      card.reset
      attempts.drop(first_miss).each { |attempt| card.schedule(attempt.quality, on: attempt.date) }
      card.save!
    end

    def attempts_by_case
      rows = ExamQuestion.joins(:exam).left_joins(:answer)
                         .where(exams: { user_id: user.id }, clinical_case_id: clinical_case_ids)
                         .pluck(
                           :clinical_case_id, :exam_id, "exams.status", "exams.feedback_timing", "exams.completed_at",
                           "answers.id", "answers.correct", "answers.error_reason", "answers.answered_at"
                         )

      rows.group_by { |row| row.first(2) }
          .filter_map { |(case_id, _exam_id), questions| attempt(questions).then { |a| [case_id, a] if a } }
          .group_by(&:first)
          .transform_values { |pairs| pairs.map(&:last).sort_by { |a| [a.date, a.exam_id] } }
    end

    # Nil while the attempt is not over. On the single page an answer can change until
    # the exam is finished; one question at a time an answer is final, and one miss
    # already decides the attempt.
    def attempt(questions)
      _case_id, exam_id, status, timing, completed_at = questions.first
      completed = status == "completed"
      answered = questions.select { |row| row[5] }
      misses = answered.reject { |row| row[6] }
      misses += questions.reject { |row| row[5] } if completed

      over = completed || (timing == "after_each" && (misses.any? || answered.size == questions.size))
      return unless over

      at = [*answered.map(&:last), (completed_at if completed)].compact.max
      Attempt.new(date: user.study_date(at), exam_id: exam_id, quality: quality(misses), missed: misses.any?)
    end

    def quality(misses)
      return CORRECT_QUALITY if misses.empty?

      misses.map { |row| MISS_QUALITIES.fetch(row[7], UNKNOWN_MISS_QUALITY) }.min
    end
  end
end

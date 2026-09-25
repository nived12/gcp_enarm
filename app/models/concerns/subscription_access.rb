# Access gating: granted premium, a paid window, an active trial, or the free daily
# allowance. `subscription_access_result` returns { allowed:, reason:, message: } so
# controllers can render a 403 or a flash unchanged — the shape ported from vittio.
#
# Paid access is a prepaid window recorded as Entitlement rows, never a subscription.
# Controllers and views ask this module; none of them may know which provider sold it.
module SubscriptionAccess
  extend ActiveSupport::Concern

  included do
    after_create :set_trial_ends_at
  end

  # Free users get a daily allowance rather than a hard wall. A simulator you cannot
  # open is a simulator nobody recommends to a classmate, and word of mouth between
  # study groups is the only distribution this product has. Ten (the owner, 2026-09-23,
  # down from 20) is one Quiz Express and the streak's daily minimum: enough to keep a
  # habit, not enough to study on for free beside a paid competitor.
  def self.free_daily_questions
    ENV.fetch("FREE_DAILY_QUESTIONS", 10).to_i
  end

  def self.trial_days
    ENV.fetch("TRIAL_DURATION_DAYS", 14).to_i
  end

  def subscription_access_result(i18n_scope: "exams.denied")
    return { allowed: true } if unlimited?

    limit = SubscriptionAccess.free_daily_questions
    return { allowed: true } if questions_answered_today < limit

    { allowed: false,
      reason: :daily_limit_reached,
      message: I18n.t("#{i18n_scope}.daily_limit_reached", limit: limit) }
  end

  def active_trial?
    trial_ends_at.present? && trial_ends_at > Time.current
  end

  def granted_premium?
    granted_premium_until.present? && granted_premium_until > Time.current
  end

  def paid_access?
    entitlements.in_force.active_at(Time.current).exists?
  end

  def active_paid_subscription?
    granted_premium? || paid_access?
  end

  # Admins and reviewers work inside the bank, so they are never capped and need no
  # granted date of their own.
  def staff_access?
    role_admin? || role_reviewer?
  end

  # No daily cap right now, for whatever reason.
  def unlimited?
    staff_access? || active_paid_subscription? || active_trial?
  end

  # When the paid window ends. Windows are stacked end to end when bought, so the
  # latest unexpired end is the end of one unbroken stretch.
  def paid_access_until
    entitlements.in_force.unexpired.maximum(:expires_at)
  end

  # Nil means uncapped, so there is no number to show. Every caller asks the user
  # rather than recomputing the rule.
  def daily_questions_limit
    return nil if unlimited?

    SubscriptionAccess.free_daily_questions
  end

  private

  # Today is the student's own calendar day, where they are, the same day the streak counts.
  def questions_answered_today
    Answer.joins(exam_question: :exam).where(exams: { user_id: id }, answered_at: study_day_times).count
  end

  def set_trial_ends_at
    update_column(:trial_ends_at, SubscriptionAccess.trial_days.days.from_now)
  end
end

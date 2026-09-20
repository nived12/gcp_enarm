# Access gating: a granted entitlement, an active trial, or a live Pay subscription.
# Ported from vittio's concern of the same name — `subscription_access_result` returns
# { allowed:, reason:, message: } so controllers can render a 403 or a flash unchanged.
module SubscriptionAccess
  extend ActiveSupport::Concern

  included do
    after_create :set_trial_ends_at
  end

  # Free users get a daily allowance rather than a hard wall. A simulator you cannot
  # open is a simulator nobody recommends to a classmate, and word of mouth between
  # study groups is the only distribution this product has.
  def self.free_daily_questions
    ENV.fetch("FREE_DAILY_QUESTIONS", 20).to_i
  end

  def subscription_access_result(i18n_scope: "exams.denied")
    return { allowed: true } if active_paid_subscription? || active_trial?

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

  def active_paid_subscription?
    granted_premium? || paid_subscription?
  end

  # Nil means uncapped, so there is no number to show. Every caller asks the user
  # rather than recomputing the rule.
  def daily_questions_limit
    return nil if active_paid_subscription? || active_trial?

    SubscriptionAccess.free_daily_questions
  end

  private

  # Pay is wired in Phase 6; until then nobody has a paid subscription and the
  # granted-premium path carries the whole product.
  def paid_subscription?
    false
  end

  def questions_answered_today
    0
  end

  def set_trial_ends_at
    trial_days = ENV.fetch("TRIAL_DURATION_DAYS", 14).to_i
    update_column(:trial_ends_at, trial_days.days.from_now)
  end
end

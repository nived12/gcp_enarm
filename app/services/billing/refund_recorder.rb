# Records money given back for one purchase. Provider-agnostic, like EntitlementGranter:
# the Stripe webhook calls it today with what the charge reports.
#
# `refunded_amount` is the provider's running total for the charge, not this refund's
# share, so a replayed or reordered event cannot count the same money twice.
#
# Only a full refund withdraws access, from now. A partial refund is a goodwill gesture or
# a correction the owner chose to make, and the policy offers no prorated refunds, so it
# is recorded and the window stays. To withdraw access, refund the whole charge.
#
# Windows bought later were queued behind this one's end. Its unused days are gone, so
# each of them moves earlier by exactly that many days: the first starts now and the
# student keeps every day still paid for, with no gap. The refunded row keeps its dates,
# so the move can always be reconstructed from its `refunded_at`.
module Billing
  class RefundRecorder < ApplicationService
    def initialize(entitlement:, refunded_amount:, full:)
      super()
      @entitlement = entitlement
      @refunded_amount = refunded_amount
      @full = full
    end

    def call
      revoked = entitlement.user.with_lock { record }
      success(entitlement: entitlement, revoked: revoked)
    end

    private

    attr_reader :entitlement, :refunded_amount, :full

    # True only for the event that withdraws access; a refund is never undone.
    def record
      entitlement.reload
      entitlement.refunded_amount = [ entitlement.refunded_amount, refunded_amount ].max
      revoking = full && !entitlement.refunded?
      entitlement.refunded_at = Time.current if revoking
      entitlement.save!
      pull_later_windows_forward if revoking
      revoking
    end

    def pull_later_windows_forward
      unused = entitlement.expires_at - [ entitlement.refunded_at, entitlement.starts_at ].max
      return unless unused.positive?

      entitlement.user.entitlements.in_force.where(starts_at: entitlement.expires_at..).find_each do |later|
        later.update!(starts_at: later.starts_at - unused, expires_at: later.expires_at - unused)
      end
    end
  end
end

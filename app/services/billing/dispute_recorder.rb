# Records a chargeback against one purchase. Provider-agnostic, like RefundRecorder: the
# Stripe webhook calls it with what the dispute reports.
#
# An open dispute withholds the window at once, since the bank has already taken the money
# back; a won one gives it back and a lost one keeps it withheld. Nothing else moves. A
# refund pulls later windows forward because its days are gone for good, but a dispute
# stays open for months and can still be won, so a queued window keeps its dates rather
# than being moved and moved back.
#
# Stripe does not deliver events in order. A dispute's opening event never overrides a
# status that dispute already has, so a `created` arriving after its `closed` changes
# nothing; a different dispute on the same charge starts over.
module Billing
  class DisputeRecorder < ApplicationService
    def initialize(entitlement:, dispute_id:, status:, opened_at:)
      super()
      @entitlement = entitlement
      @dispute_id = dispute_id
      @status = status
      @opened_at = opened_at
    end

    def call
      changed = entitlement.user.with_lock { record }
      success(entitlement: entitlement, changed: changed)
    end

    private

    attr_reader :entitlement, :dispute_id, :status, :opened_at

    # True only when the dispute's status changed, so a replay reports nothing twice.
    def record
      entitlement.reload
      same_dispute = entitlement.dispute_id == dispute_id
      return false if same_dispute && (status == "open" || entitlement.dispute_status == status)

      entitlement.update!(dispute_id: dispute_id, dispute_status: status, disputed_at: opened_at)
      true
    end
  end
end

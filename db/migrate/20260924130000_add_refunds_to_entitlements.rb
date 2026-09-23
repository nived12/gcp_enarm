class AddRefundsToEntitlements < ActiveRecord::Migration[8.1]
  def change
    # A refund is recorded on the purchase it reverses, never by deleting it: the row stays
    # the record of the sale. `refunded_amount` accumulates partial refunds; `refunded_at`
    # is set only once the whole charge is back with the student, and from then on the
    # window grants nothing.
    change_table :entitlements, bulk: true do |t|
      t.decimal :refunded_amount, precision: 12, scale: 2, null: false, default: 0
      t.datetime :refunded_at
    end

    # Stripe reports a refund against a charge, whose only link back to the sale is the
    # PaymentIntent id kept in the Checkout Session payload.
    add_index :entitlements, "(raw_payload ->> 'payment_intent')", name: "index_entitlements_on_payment_intent"
  end
end

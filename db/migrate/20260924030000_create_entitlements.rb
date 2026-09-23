class CreateEntitlements < ActiveRecord::Migration[8.1]
  def change
    # The one place paid access comes from. Append-only: a second purchase is a second
    # row, so the table is the purchase history and nothing is ever edited in place.
    create_table :entitlements do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.string :plan, null: false
      t.string :source, null: false

      # The provider's own identifier for the purchase — a Checkout Session id for Stripe.
      # Unique per source, which is what makes a replayed webhook harmless.
      t.string :external_id, null: false
      t.datetime :starts_at, null: false
      t.datetime :expires_at, null: false

      # What was actually charged, never read back from the plan catalog.
      t.decimal :amount, precision: 12, scale: 2, null: false, default: 0
      t.string :currency, null: false, default: "MXN"
      t.jsonb :raw_payload, null: false, default: {}

      t.timestamps
    end

    add_index :entitlements, %i[source external_id], unique: true
    add_index :entitlements, %i[user_id expires_at]

    # Every provider event we have acted on. Providers deliver at least once, so the
    # event id is recorded in the same transaction as its effect.
    create_table :webhook_events do |t|
      t.string :provider, null: false
      t.string :external_id, null: false
      t.string :event_type, null: false

      t.timestamps
    end

    add_index :webhook_events, %i[provider external_id], unique: true
  end
end

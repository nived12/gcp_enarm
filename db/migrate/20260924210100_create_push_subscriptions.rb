# One row per browser a student allowed to show notifications: what PushManager.subscribe
# returned there. The endpoint identifies the device to its push service.
class CreatePushSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :push_subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.text :endpoint, null: false
      t.string :p256dh_key, null: false
      t.string :auth_key, null: false
      t.string :user_agent
      t.timestamps
    end
    add_index :push_subscriptions, :endpoint, unique: true
  end
end

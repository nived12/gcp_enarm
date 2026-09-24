# The ledger that keeps reminders from repeating. A row is written before anything is
# sent, and the unique index is what makes a second attempt for the same student, day
# and slot fail instead of sending twice.
class CreateReminderDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :reminder_deliveries do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.date :local_date, null: false
      t.string :slot, null: false
      t.string :kind, null: false
      t.jsonb :channels, null: false, default: []
      t.timestamps
    end
    add_index :reminder_deliveries, %i[user_id local_date slot], unique: true
  end
end

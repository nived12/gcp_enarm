class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.string :name
      t.string :locale, null: false, default: "es"
      t.string :role, null: false, default: "student"
      t.integer :exam_year
      t.datetime :trial_ends_at
      # Premium handed out rather than sold: entitlement only, no Pay row, so every
      # billing path correctly finds nothing to manage.
      t.datetime :granted_premium_until

      t.timestamps
    end

    add_index :users, :email_address, unique: true
    add_index :users, :granted_premium_until
  end
end

# An account a student can sign in with besides a password — Google today, others later.
# `uid` is the provider's own stable id for the person (Google's `sub`); the email is kept
# only to show which account is linked, since the person can change it at the provider.
# An account signed up through Google alone has no password, so the digest becomes optional.
class CreateIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :identities do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.string :provider, null: false
      t.string :uid, null: false
      t.string :email
      t.timestamps
    end
    add_index :identities, %i[provider uid], unique: true
    add_index :identities, %i[user_id provider], unique: true

    change_column_null :users, :password_digest, true
  end
end

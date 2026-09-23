# Accounts made with a password prove their address by following a link; Google-made
# ones arrive proven. Every account that exists before this was made by hand or by us,
# so each is counted as verified the day it was created.
class AddEmailVerifiedAtToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :email_verified_at, :datetime
    execute "UPDATE users SET email_verified_at = created_at"
  end

  def down
    remove_column :users, :email_verified_at
  end
end

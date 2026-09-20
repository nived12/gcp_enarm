class RenameEmailAddressToEmailOnUsers < ActiveRecord::Migration[8.1]
  def change
    # email_address is the Rails 8 authentication generator's name for it. Nothing
    # else in the domain is called an address, so the shorter name is the clearer one.
    rename_column :users, :email_address, :email
  end
end

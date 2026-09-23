# One free-text name becomes given names and surnames. The split cannot be exact — "María
# José Pérez" (two given names, one surname) and "Ana Pérez López" (one and two) have the
# same shape — so it follows the Mexican norm of two surnames and lets the student correct
# it on /account:
#
#   one word          -> all given name, no surname      "Gabriela"
#   two words         -> one given name, one surname     "Gabriela | Guadarrama"
#   three or more     -> the last two are surnames       "Ana | Pérez López", "María José | Pérez López"
#
# A lowercase particle just before the surnames belongs to them ("Juan | de la Cruz Pérez").
# A blank name leaves the part of the email before the @ as the given name, because every
# account needs something to greet.
class SplitUserName < ActiveRecord::Migration[8.1]
  PARTICLES = %w[de del la las los y da das do dos van von].freeze

  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  def up
    add_column :users, :first_name, :string
    add_column :users, :last_name, :string

    MigrationUser.reset_column_information
    MigrationUser.find_each do |user|
      first_name, last_name = split(user.name.to_s)
      user.update_columns(first_name: first_name.presence || user.email.split("@").first, last_name: last_name)
    end

    change_column_null :users, :first_name, false
    remove_column :users, :name
  end

  def down
    add_column :users, :name, :string
    execute "UPDATE users SET name = concat_ws(' ', first_name, last_name)"
    remove_column :users, :first_name
    remove_column :users, :last_name
  end

  private

  def split(name)
    words = name.squish.split
    return [ words.first, nil ] if words.size < 2

    surname_count = words.size == 2 ? 1 : 2
    surname_count += 1 while surname_count < words.size - 1 && PARTICLES.include?(words[-surname_count - 1])
    [ words[0...-surname_count].join(" "), words.last(surname_count).join(" ") ]
  end
end

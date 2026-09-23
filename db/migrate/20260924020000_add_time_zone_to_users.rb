# Mexico is not one time zone — Sonora, Baja California and Quintana Roo differ from the
# centre — and the study day ends at 4 a.m. where the student is, so the zone is stored.
class AddTimeZoneToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :time_zone, :string, null: false, default: "America/Mexico_City"
  end
end

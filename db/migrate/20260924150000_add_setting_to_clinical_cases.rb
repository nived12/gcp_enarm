# Where a case happens, beside what it is about. The convocatoria frames every case in
# Salud Pública, Urgencias or Medicina Familiar and draws its content from the troncales,
# so a case is filed under its subject (specialty_id) and its setting (setting_id), both
# pointing at specialties. Nullable: a setting nobody has read yet is unknown, not absent.
class AddSettingToClinicalCases < ActiveRecord::Migration[8.1]
  def change
    add_reference :clinical_cases, :setting, foreign_key: { to_table: :specialties }, index: true
  end
end

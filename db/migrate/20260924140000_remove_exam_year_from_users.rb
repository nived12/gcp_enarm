# Created with the users table and never read or written since: the exam date lives on
# StudyPlan#exam_date.
class RemoveExamYearFromUsers < ActiveRecord::Migration[8.1]
  def change
    remove_column :users, :exam_year, :integer
  end
end

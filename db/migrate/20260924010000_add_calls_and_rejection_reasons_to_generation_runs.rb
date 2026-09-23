class AddCallsAndRejectionReasonsToGenerationRuns < ActiveRecord::Migration[8.1]
  def change
    # Completions actually made. `attempts` counts cases plus rejected questions on a
    # generation run, which is not a number of requests, and every cost estimate needs one.
    add_column :generation_runs, :calls, :integer, default: 0, null: false
    add_column :generation_runs, :rejection_reasons, :jsonb, default: {}, null: false
  end
end

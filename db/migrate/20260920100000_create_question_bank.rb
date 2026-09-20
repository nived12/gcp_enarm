class CreateQuestionBank < ActiveRecord::Migration[8.1]
  def change
    # One batch of generation, with what it actually cost. Every case points at the run
    # that made it, so a bad prompt or a bad model can be found and retired wholesale
    # rather than case by case.
    create_table :generation_runs do |t|
      t.string :purpose, null: false
      t.string :provider, null: false
      t.string :model, null: false
      t.string :status, null: false, default: "running"

      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0

      # Eight decimal places because a single call can cost a fraction of a cent and
      # the whole point of this table is that those fractions add up to the bill.
      t.decimal :cost_usd, precision: 12, scale: 8, null: false, default: 0

      t.integer :cases_created, null: false, default: 0

      # How many attempts it took to get the accepted cases. The bake-off compares
      # models on this as well as on quality: a cheaper model that needs two passes
      # is not cheaper.
      t.integer :attempts, null: false, default: 0
      t.integer :rejections, null: false, default: 0

      t.text :notes
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    # The ENARM is clinical cases with two to three questions each, never standalone
    # questions, so that is the unit here too.
    create_table :clinical_cases do |t|
      t.text :stem, null: false
      t.references :topic, foreign_key: true
      t.references :specialty, foreign_key: true
      t.references :guideline, foreign_key: true
      t.references :generation_run, foreign_key: true

      t.string :locale, null: false, default: "es"

      # CIFRHS grades every reactivo Alta/Media/Baja and those grades break ties.
      # Seeded from the evidence grade of the recommendation behind the case, then
      # recalibrated from real answer data — which is what CIFRHS itself does.
      t.string :difficulty, null: false, default: "medium"

      t.string :status, null: false, default: "draft"
      t.string :source, null: false, default: "gpc_generated"

      # Set by Questions::Verifier, on a different model family than the generator.
      # Nothing but "supported" may reach published.
      t.string :verification_verdict
      t.text :verification_notes
      t.datetime :verified_at

      t.timestamps
    end

    create_table :questions do |t|
      t.references :clinical_case, null: false, foreign_key: true
      t.integer :position, null: false
      t.text :text, null: false
      t.text :explanation

      # The recommendation this question was generated from, and the span of it the
      # model claims to be using. source_quote must be a literal substring of
      # Recommendation#text — checked in Ruby before the row is written, which is what
      # makes a cheap model acceptable here.
      t.references :recommendation, foreign_key: true
      t.text :source_quote

      t.timestamps
    end

    # Exactly four per question. A table rather than jsonb specifically so that *which*
    # wrong answer a student picks is queryable — that is the most useful weak-spot
    # signal in the product.
    create_table :answer_options do |t|
      t.references :question, null: false, foreign_key: true
      t.integer :position, null: false
      t.text :text, null: false
      t.boolean :correct, null: false, default: false
      t.timestamps
    end

    add_index :generation_runs, [:provider, :model]
    add_index :generation_runs, :status
    add_index :clinical_cases, [:status, :difficulty]
    add_index :clinical_cases, [:topic_id, :status]
    add_index :clinical_cases, :verification_verdict
    add_index :questions, [:clinical_case_id, :position], unique: true
    add_index :answer_options, [:question_id, :position], unique: true
  end
end

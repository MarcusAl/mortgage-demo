class CreateAssessments < ActiveRecord::Migration[8.1]
  def change
    create_table :assessments do |t|
      t.references :mortgage_application, null: false, foreign_key: true, index: { unique: true }
      t.decimal :ltv, precision: 5, scale: 2
      t.decimal :dti, precision: 5, scale: 2
      t.integer :loan_amount_cents
      t.integer :max_borrowing_cents
      t.integer :decision
      t.integer :status, null: false, default: 0
      t.text :explanation
      t.timestamps
    end
  end
end

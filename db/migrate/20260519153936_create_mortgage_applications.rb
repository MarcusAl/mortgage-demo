class CreateMortgageApplications < ActiveRecord::Migration[8.1]
  def change
    create_table :mortgage_applications do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :annual_income_cents, null: false
      t.integer :monthly_expenses_cents, null: false
      t.integer :deposit_cents, null: false
      t.integer :property_value_cents, null: false
      t.integer :term_years, null: false
      t.timestamps
    end
  end
end

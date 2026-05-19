# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_19_153937) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "assessments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "decision"
    t.decimal "dti", precision: 5, scale: 2
    t.text "explanation"
    t.integer "loan_amount_cents"
    t.decimal "ltv", precision: 5, scale: 2
    t.integer "max_borrowing_cents"
    t.bigint "mortgage_application_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["mortgage_application_id"], name: "index_assessments_on_mortgage_application_id", unique: true
  end

  create_table "mortgage_applications", force: :cascade do |t|
    t.integer "annual_income_cents", null: false
    t.datetime "created_at", null: false
    t.integer "deposit_cents", null: false
    t.integer "monthly_expenses_cents", null: false
    t.integer "property_value_cents", null: false
    t.integer "term_years", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_mortgage_applications_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "api_token", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "updated_at", null: false
    t.index ["api_token"], name: "index_users_on_api_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "assessments", "mortgage_applications"
  add_foreign_key "mortgage_applications", "users"
end

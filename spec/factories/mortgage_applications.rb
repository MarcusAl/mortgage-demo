FactoryBot.define do
  factory :mortgage_application do
    user
    annual_income_cents { 60_000_00 }
    monthly_expenses_cents { 1_500_00 }
    deposit_cents { 50_000_00 }
    property_value_cents { 250_000_00 }
    term_years { 25 }
  end
end

FactoryBot.define do
  factory :assessment do
    mortgage_application
    status { :pending }

    trait :completed do
      status { :completed }
      decision { :approved }
      ltv { 80.0 }
      dti { 30.0 }
      loan_amount_cents { 200_000_00 }
      max_borrowing_cents { 270_000_00 }
      explanation { "Application approved." }
    end

    trait :failed do
      status { :failed }
    end
  end
end

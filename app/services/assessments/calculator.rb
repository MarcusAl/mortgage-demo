module Assessments
  class Calculator
    MAX_LTV = 95.0
    MAX_DTI = 50.0
    INCOME_MULTIPLE = 4.5

    def initialize(mortgage_application)
      @mortgage_application = mortgage_application
    end

    def call
      return unless @mortgage_application

      {
        ltv: ltv,
        dti: dti,
        loan_amount_cents: loan_amount_cents,
        max_borrowing_cents: max_borrowing_cents,
        decision: decision,
        explanation: explanation
      }
    end

    private

    def loan_amount_cents
      @mortgage_application.property_value_cents - @mortgage_application.deposit_cents
    end

    def ltv
      return 100.0 if @mortgage_application.property_value_cents.zero?

      (loan_amount_cents.to_f / @mortgage_application.property_value_cents * 100).round(2)
    end

    def dti
      monthly_income = @mortgage_application.annual_income_cents / 12.0
      return 0.0 if monthly_income.zero?

      (@mortgage_application.monthly_expenses_cents.to_f / monthly_income * 100).round(2)
    end

    def max_borrowing_cents
      (@mortgage_application.annual_income_cents * INCOME_MULTIPLE).to_i
    end

    def decision
      decline_reasons.empty? ? :approved : :declined
    end

    def explanation
      if decline_reasons.empty?
        "Application approved. LTV of #{format("%.2f", ltv)}% is within the #{MAX_LTV.to_i}% limit. " \
          "DTI of #{format("%.2f", dti)}% is within the #{MAX_DTI.to_i}% limit. " \
          "Loan amount is within the maximum borrowing of #{INCOME_MULTIPLE}x annual income."
      else
        "Application declined. #{decline_reasons.join(" ")}"
      end
    end

    def decline_reasons
      @decline_reasons ||= [].tap do |reasons|
        if ltv > MAX_LTV
          reasons << "LTV of #{format("%.2f", ltv)}% exceeds the #{MAX_LTV.to_i}% limit."
        end

        if dti > MAX_DTI
          reasons << "DTI of #{format("%.2f", dti)}% exceeds the #{MAX_DTI.to_i}% limit."
        end

        if loan_amount_cents > max_borrowing_cents
          reasons << "Loan amount exceeds the maximum borrowing of #{INCOME_MULTIPLE}x annual income."
        end
      end
    end
  end
end

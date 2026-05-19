class MortgageApplicationPresenter
  def initialize(mortgage_application)
    @mortgage_application = mortgage_application
  end

  def as_json
    {
      id: @mortgage_application.id,
      annual_income_cents: @mortgage_application.annual_income_cents,
      monthly_expenses_cents: @mortgage_application.monthly_expenses_cents,
      deposit_cents: @mortgage_application.deposit_cents,
      property_value_cents: @mortgage_application.property_value_cents,
      term_years: @mortgage_application.term_years,
      created_at: @mortgage_application.created_at,
      assessment: @mortgage_application.assessment ? AssessmentPresenter.new(@mortgage_application.assessment).as_json : nil
    }
  end
end

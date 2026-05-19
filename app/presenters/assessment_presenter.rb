class AssessmentPresenter
  def initialize(assessment)
    @assessment = assessment
  end

  def as_json
    {
      id: @assessment.id,
      status: @assessment.status,
      decision: @assessment.decision,
      ltv: @assessment.ltv,
      dti: @assessment.dti,
      loan_amount_cents: @assessment.loan_amount_cents,
      max_borrowing_cents: @assessment.max_borrowing_cents,
      explanation: @assessment.explanation
    }
  end
end

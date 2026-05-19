class AssessmentJob < ApplicationJob
  queue_as :default

  retry_on ActiveRecord::StatementInvalid, attempts: 2, wait: 5.seconds
  discard_on ActiveRecord::RecordNotFound

  def perform(mortgage_application_id)
    mortgage_application = MortgageApplication.find(mortgage_application_id)
    assessment = mortgage_application.assessment
    assessment.processing!

    result = Assessments::Calculator.new(mortgage_application).call
    assessment.update!(result.merge(status: :completed))
  rescue ActiveRecord::StatementInvalid
    assessment&.update(status: :failed) if assessment&.persisted?
    raise
  rescue ActiveRecord::RecordInvalid => e
    assessment&.update(status: :failed) if assessment&.persisted?
    Rails.logger.error("Assessment failed for application #{mortgage_application_id}: #{e.message}")
  end
end

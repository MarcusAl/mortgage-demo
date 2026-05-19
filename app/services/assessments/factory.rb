module Assessments
  class Factory
    def initialize(mortgage_application)
      @mortgage_application = mortgage_application
    end

    def call
      existing = @mortgage_application.assessment
      return existing if existing

      assessment = @mortgage_application.build_assessment(status: :pending)
      assessment.save!
      AssessmentJob.perform_later(@mortgage_application.id)
      assessment
    rescue ActiveRecord::RecordNotUnique
      @mortgage_application.reload_assessment
    end
  end
end

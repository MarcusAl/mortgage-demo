class AssessmentJob < ApplicationJob
  queue_as :default

  def perform(mortgage_application_id)
  end
end

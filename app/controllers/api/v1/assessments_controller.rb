module Api
  module V1
    class AssessmentsController < ApplicationController
      before_action :set_mortgage_application

      def create
        assessment = Assessments::Factory.new(@mortgage_application).call()

        if assessment.pending?
          render json: { data: AssessmentPresenter.new(assessment).as_json }, status: :accepted
        else
          render json: { data: AssessmentPresenter.new(assessment).as_json }
        end
      end

      def show
        assessment = @mortgage_application.assessment

        if assessment
          render json: { data: AssessmentPresenter.new(assessment).as_json }
        else
          render json: { errors: [ "Not found" ] }, status: :not_found
        end
      end

      private

      def set_mortgage_application
        @mortgage_application = current_user.mortgage_applications.find(params[:mortgage_application_id])
      rescue ActiveRecord::RecordNotFound
        render json: { errors: [ "Not found" ] }, status: :not_found
      end
    end
  end
end

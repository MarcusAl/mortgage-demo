module Api
  module V1
    class MortgageApplicationsController < ApplicationController
      before_action :set_mortgage_application, only: :show

      def index
        mortgage_applications = current_user.mortgage_applications.includes(:assessment)
        render json: { data: mortgage_applications.map { |app| index_json(app) } }
      end

      def show
        render json: { data: show_json(@mortgage_application) }
      end

      def create
        mortgage_application = current_user.mortgage_applications.new(application_params)

        if mortgage_application.save
          render json: { data: show_json(mortgage_application) }, status: :created
        else
          render json: { errors: mortgage_application.errors.full_messages }, status: :unprocessable_content
        end
      end

      private

      def set_mortgage_application
        @mortgage_application = current_user.mortgage_applications.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { errors: [ "Not found" ] }, status: :not_found
      end

      def application_params
        params.require(:mortgage_application).permit(
          :annual_income_cents,
          :monthly_expenses_cents,
          :deposit_cents,
          :property_value_cents,
          :term_years
        )
      end

      def index_json(mortgage_application)
        {
          id: mortgage_application.id,
          annual_income_cents: mortgage_application.annual_income_cents,
          monthly_expenses_cents: mortgage_application.monthly_expenses_cents,
          deposit_cents: mortgage_application.deposit_cents,
          property_value_cents: mortgage_application.property_value_cents,
          term_years: mortgage_application.term_years,
          assessment_status: mortgage_application.assessment&.status,
          created_at: mortgage_application.created_at
        }
      end

      def show_json(mortgage_application)
        {
          id: mortgage_application.id,
          annual_income_cents: mortgage_application.annual_income_cents,
          monthly_expenses_cents: mortgage_application.monthly_expenses_cents,
          deposit_cents: mortgage_application.deposit_cents,
          property_value_cents: mortgage_application.property_value_cents,
          term_years: mortgage_application.term_years,
          created_at: mortgage_application.created_at,
          assessment: assessment_json(mortgage_application.assessment)
        }
      end

      def assessment_json(assessment)
        return nil unless assessment

        {
          id: assessment.id,
          status: assessment.status,
          decision: assessment.decision,
          ltv: assessment.ltv,
          dti: assessment.dti,
          loan_amount_cents: assessment.loan_amount_cents,
          max_borrowing_cents: assessment.max_borrowing_cents,
          explanation: assessment.explanation
        }
      end
    end
  end
end

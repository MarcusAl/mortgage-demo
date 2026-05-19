module Api
  module V1
    class MortgageApplicationsController < ApplicationController
      before_action :set_mortgage_application, only: :show

      def index
        mortgage_applications = current_user.mortgage_applications.includes(:assessment)
        render json: { data: mortgage_applications.map { |ma| MortgageApplicationPresenter.new(ma).as_json } }
      end

      def show
        render json: { data: MortgageApplicationPresenter.new(@mortgage_application).as_json }
      end

      def create
        mortgage_application = current_user.mortgage_applications.new(application_params)

        if mortgage_application.save
          render json: { data: MortgageApplicationPresenter.new(mortgage_application).as_json }, status: :created
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
    end
  end
end

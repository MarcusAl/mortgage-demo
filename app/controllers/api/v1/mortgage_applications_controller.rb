module Api
  module V1
    class MortgageApplicationsController < ApplicationController
      def index
        render json: { data: [] }
      end

      def show
        render json: { data: {} }
      end

      def create
        render json: { data: {} }, status: :created
      end
    end
  end
end

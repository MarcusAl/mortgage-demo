module Api
  module V1
    class AssessmentsController < ApplicationController
      def show
        render json: { data: {} }
      end

      def create
        render json: { data: {} }, status: :accepted
      end
    end
  end
end

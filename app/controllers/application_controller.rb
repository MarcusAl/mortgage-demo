class ApplicationController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods

  before_action :authenticate

  private

  def authenticate
    authenticate_with_http_token do |token, _options|
      @current_user = User.find_by(api_token: token)
    end

    render json: { errors: [ "Unauthorized" ] }, status: :unauthorized unless @current_user
  end

  def current_user
    @current_user
  end
end

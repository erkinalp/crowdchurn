# frozen_string_literal: true

module Api
  class ApiController < ActionController::API
    include ActionController::HttpAuthentication::Token::ControllerMethods

    before_action :set_default_format

    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActionController::ParameterMissing, with: :bad_request

    private

    def set_default_format
      request.format = :json
    end

    def authenticate_api_user!
      authenticate_or_request_with_http_token do |token, options|
        @current_api_user = User.find_by(api_token: token)
      end

      render json: { error: 'Unauthorized' }, status: :unauthorized unless @current_api_user
    end

    def current_api_user
      @current_api_user
    end

    def api_user_signed_in?
      @current_api_user.present?
    end

    def not_found
      render json: { error: 'Resource not found' }, status: :not_found
    end

    def bad_request(exception)
      render json: { error: exception.message }, status: :bad_request
    end
  end
end

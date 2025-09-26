require 'jwt'

module Api
  module V1
    class SessionsController < ApplicationController
      before_action :authenticate_request!, only: [:logged_in?]

      # POST /api/v1/login
      def create
        user = User.find_by(email_address: params[:session][:email_address])
        if user&.authenticate(params[:session][:password])
          token = encode_jwt(user_id: user.id)
          render json: { token:, user: user.slice(:id, :email_address, :role) }
        else
          render json: { error: "Invalid credentials" }, status: :unauthorized
        end
      end

      # GET /api/v1/logged_in
      def logged_in?
        # This action relies on an authentication method that decodes the token
        # from the Authorization header and sets @current_user.
        if @current_user
          render json: { logged_in: true, user: @current_user }, status: :ok
        else
          render json: { logged_in: false }, status: :unauthorized
        end
      end

      # DELETE /api/v1/logout
      def destroy
        # TODO: Make sure JWT is deleted on the frontend
        render json: { status: 'Logged out successfully' }, status: :ok
      end
    
      private

      def encode_jwt(payload)
        # Explicitly set the algorithm for better security.
        # HS256 is the default, but it's best practice to be explicit.
        algorithm = 'HS256'
        payload_with_exp = payload.merge(exp: 24.hours.from_now.to_i)
        JWT.encode(payload_with_exp, Rails.application.secret_key_base, algorithm)
      end
    end
  end
end

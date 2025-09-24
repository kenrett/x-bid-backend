require 'jwt'

module Api
  module V1
    class SessionsController < ApplicationController
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
        JWT.encode(payload.merge(exp: 24.hours.from_now.to_i), Rails.application.secret_key_base)
      end
    end
  end
end

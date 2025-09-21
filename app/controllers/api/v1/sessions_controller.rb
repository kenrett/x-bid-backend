module Api
  module V1
    class SessionsController < ApplicationController
      def create
      user = User.find_by(email: params[:email])
      if user&.authenticate(params[:password])
        token = encode_jwt(user_id: user.id)
        render json: { token:, user: user.slice(:id, :email, :role) }
      else
        render json: { error: "Invalid credentials" }, status: :unauthorized
      end

    private

    def encode_jwt(payload)
      JWT.encode(payload.merge(exp: 24.hours.from_now.to_i), Rails.application.secret_key_base)
    end
      end
    end
  end
end

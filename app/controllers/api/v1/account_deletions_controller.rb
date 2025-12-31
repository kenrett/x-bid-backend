module Api
  module V1
    class AccountDeletionsController < ApplicationController
      before_action :authenticate_request!
      rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing

      # DELETE /api/v1/account
      # @summary Disable (soft delete) the current account and revoke sessions
      # @request_body Delete account payload (application/json) [!AccountDeleteRequest]
      # @response Success (200) [Hash{ status: String }]
      # @response Unauthorized (401) [Error]
      # @response Unprocessable content (422) [Error]
      def create
        result = Account::DeleteAccount.new(
          user: @current_user,
          current_password: delete_params.fetch(:current_password),
          confirmation: delete_params.fetch(:confirmation)
        ).call
        return render_error(code: result.code, message: result.message, status: result.http_status) unless result.ok?

        render json: { status: "deleted" }, status: :ok
      end
      alias_method :destroy, :create

      private

      def delete_params
        (params[:account].presence || params).permit(:current_password, :confirmation)
      end

      def handle_parameter_missing(exception)
        render_error(code: :bad_request, message: exception.message, status: :bad_request)
      end
    end
  end
end

module Api
  module V1
    class AccountEmailsController < ApplicationController
      before_action :authenticate_request!
      rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing

      # POST /api/v1/account/email-change
      # @summary Request an email address change (verification required)
      # @request_body Change email payload (application/json) [!ChangeEmailRequest]
      # @response Accepted (202) [Hash{ status: String }]
      # @response Unauthorized (401) [Error]
      # @response Unprocessable content (422) [Error]
      # @response Too many requests (429) [Error]
      def change
        result = Account::RequestEmailChange.new(
          user: @current_user,
          new_email_address: email_params.fetch(:new_email_address),
          current_password: email_params.fetch(:current_password),
          environment: Rails.env
        ).call

        return render_error(code: result.code, message: result.message, status: result.http_status) unless result.ok?

        render json: { status: "verification_sent" }, status: :accepted
      end

      private

      def email_params
        (params[:email].presence || params).permit(:new_email_address, :current_password)
      end

      def handle_parameter_missing(exception)
        render_error(code: :bad_request, message: exception.message, status: :bad_request)
      end
    end
  end
end

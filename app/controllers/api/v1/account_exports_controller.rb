module Api
  module V1
    class AccountExportsController < ApplicationController
      before_action :authenticate_request!
      rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing

      # POST /api/v1/account/exports
      # @summary Request an account export (MVP)
      # @response Accepted (202) [AccountExportResponse]
      # @response Unauthorized (401) [Error]
      def create
        result = Account::CreateExport.new(user: @current_user, environment: Rails.env).call
        return render_error(code: result.code, message: result.message, status: result.http_status) unless result.ok?

        render json: { export: result.export_payload }, status: :accepted
      end

      # GET /api/v1/account/exports/latest
      # @summary Get the latest account export status
      # @response Success (200) [AccountExportResponse]
      # @response Unauthorized (401) [Error]
      def latest
        result = Account::LatestExport.new(user: @current_user).call
        return render_error(code: result.code, message: result.message, status: result.http_status) unless result.ok?

        render json: { export: result.export_payload }, status: :ok
      end

      private

      def handle_parameter_missing(exception)
        render_error(code: :bad_request, message: exception.message, status: :bad_request)
      end
    end
  end
end

module Api
  module V1
    class AccountExportsController < ApplicationController
      before_action :authenticate_request!
      rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing

      # POST /api/v1/account/data/export
      # @summary Request an account export (MVP)
      # @response Accepted (202) [AccountExportResponse]
      # @response Unauthorized (401) [Error]
      def create
        result = Account::CreateExport.new(user: @current_user, environment: Rails.env).call
        return render_error(code: result.code, message: result.message, status: result.http_status) unless result.ok?

        render json: { export: result.export_payload }, status: :accepted
      end

      # GET /api/v1/account/data/export
      # @summary Get the latest account export status
      # @response Success (200) [AccountExportResponse]
      # @response Unauthorized (401) [Error]
      def show
        result = Account::LatestExport.new(user: @current_user).call
        return render_error(code: result.code, message: result.message, status: result.http_status) unless result.ok?

        render json: { export: result.export_payload }, status: :ok
      end

      # GET /api/v1/account/export/download
      # @summary Download an account export payload via signed URL
      # @response Success (200) [AccountExportData]
      # @response Unauthorized (401) [Error]
      def download
        token = params.require(:token)
        payload = Account::ExportUrlSigner.new.verify!(token)
        user_id = payload[:user_id] || payload["user_id"]
        export_id = payload[:export_id] || payload["export_id"]

        if @current_user&.id != user_id.to_i
          return render_error(code: :forbidden, message: "Not authorized", status: :forbidden)
        end
        export = AccountExport.find_by(id: export_id, user_id: user_id)
        return render_error(code: :not_found, message: "Export not found", status: :not_found) unless export&.ready?

        AuditLogger.log(
          action: "account.export.downloaded",
          actor: @current_user,
          user: export.user,
          target: export,
          payload: { export_id: export.id }
        )

        render json: export.payload, status: :ok
      rescue ArgumentError => e
        render_error(code: :invalid_token, message: e.message, status: :unauthorized)
      end

      private

      # Backwards-compatible internal name (no longer routed).
      def handle_parameter_missing(exception)
        render_error(code: :bad_request, message: exception.message, status: :bad_request)
      end
    end
  end
end

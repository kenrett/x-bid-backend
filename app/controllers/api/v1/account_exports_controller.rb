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

      # GET /api/v1/account/export
      # @summary Return an account export (or start async export)
      # Returns the export JSON when ready; otherwise returns export metadata (202) so clients can poll.
      # @response Success (200) [Hash]
      # @response Accepted (202) [AccountExportResponse]
      # @response Unauthorized (401) [Error]
      def export
        latest = Account::LatestExport.new(user: @current_user).call
        return render_error(code: latest.code, message: latest.message, status: latest.http_status) unless latest.ok?

        latest_payload = latest.export_payload.is_a?(Hash) ? latest.export_payload.with_indifferent_access : nil
        if latest_payload
          if latest_payload[:status].to_s == "ready" && latest_payload[:data].is_a?(Hash)
            return render json: latest_payload[:data], status: :ok
          end

          if latest_payload[:status].to_s == "ready" && latest_payload[:download_url].present?
            return render json: { download_url: latest_payload[:download_url] }, status: :ok
          end
        end

        created = Account::CreateExport.new(user: @current_user, environment: Rails.env).call
        return render_error(code: created.code, message: created.message, status: created.http_status) unless created.ok?

        created_payload = created.export_payload.is_a?(Hash) ? created.export_payload.with_indifferent_access : nil
        if created_payload && created_payload[:status].to_s == "ready" && created_payload[:data].is_a?(Hash)
          return render json: created_payload[:data], status: :ok
        end

        render json: { export: created_payload }, status: :accepted
      end

      private

      # Backwards-compatible internal name (no longer routed).
      def latest
        show
      end

      def handle_parameter_missing(exception)
        render_error(code: :bad_request, message: exception.message, status: :bad_request)
      end
    end
  end
end

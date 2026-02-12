module Api
  module V1
    class UploadsController < ApplicationController
      before_action :authenticate_request!, except: :show

      DEFAULT_CONTENT_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze
      DEFAULT_PUBLIC_UPLOAD_URL_EXPIRES_IN_SECONDS = 300

      # POST /api/v1/uploads
      def create
        blob = nil
        uploaded_file = params[:file]
        if uploaded_file.nil?
          return render_invalid_upload!("file is required")
        end
        unless uploaded_file.is_a?(ActionDispatch::Http::UploadedFile)
          return render_invalid_upload!("file must be an uploaded file")
        end

        if uploaded_file.size.to_i > max_upload_bytes
          return render_invalid_upload!(
            "File exceeds max upload size",
            details: { max_bytes: max_upload_bytes, byte_size: uploaded_file.size.to_i }
          )
        end

        if allowed_content_types.any? && !allowed_content_types.include?(uploaded_file.content_type)
          return render_invalid_upload!(
            "Unsupported content type",
            details: { allowed: allowed_content_types, content_type: uploaded_file.content_type }
          )
        end

        ActiveStorage::Current.url_options = { host: request.base_url }

        blob = ActiveStorage::Blob.create_and_upload!(
          io: uploaded_file,
          filename: uploaded_file.original_filename,
          content_type: uploaded_file.content_type
        )
        UploadAuthorization.create!(user: current_user, blob: blob)

        log_upload(success: true, uploaded_file: uploaded_file, blob: blob)

        render json: upload_payload(blob), status: :ok
      rescue ActiveStorage::IntegrityError, ActiveStorage::Error, ActiveRecord::ActiveRecordError => e
        blob&.purge_later
        log_upload(success: false, uploaded_file: uploaded_file, error: e)
        render_invalid_upload!("Upload failed", details: { error_class: e.class.name })
      end

      # GET /api/v1/uploads/:signed_id
      # @summary Serve upload content by signed id
      # Redirects to the Active Storage service URL for image rendering in public auction views.
      # Redirect responses include cache hints aligned to the signed URL expiration.
      # @response Not found (404) [Error]
      # @no_auth
      def show
        blob = ActiveStorage::Blob.find_signed(params[:signed_id])
        unless blob
          return render_error(code: :not_found, message: "Upload not found", status: :not_found)
        end

        unless UploadAuthorization.exists?(blob_id: blob.id)
          return render_error(code: :not_found, message: "Upload not found", status: :not_found)
        end

        ActiveStorage::Current.url_options = { host: request.base_url }
        service_url_expires_in = public_upload_url_expires_in

        response.set_header("Cross-Origin-Resource-Policy", "cross-origin")
        response.set_header("Cache-Control", "public, max-age=#{service_url_expires_in}")
        redirect_to build_service_url(blob, expires_in: service_url_expires_in), allow_other_host: true
      rescue ActiveStorage::FileNotFoundError
        render_error(code: :not_found, message: "Upload not found", status: :not_found)
      end

      private

      def upload_payload(blob)
        expires_in = ActiveStorage.service_urls_expire_in
        {
          url: build_service_url(blob, expires_in: expires_in),
          public_url: "#{request.base_url}/api/v1/uploads/#{blob.signed_id}",
          expires_in: expires_in.to_i,
          signed_id: blob.signed_id,
          filename: blob.filename.to_s,
          content_type: blob.content_type,
          byte_size: blob.byte_size
        }
      end

      def max_upload_bytes
        max_mb = Integer(ENV.fetch("UPLOAD_MAX_MB", "25"))
        max_mb * 1024 * 1024
      rescue ArgumentError
        25 * 1024 * 1024
      end

      def build_service_url(blob, expires_in:)
        return blob.service_url(expires_in: expires_in) if blob.respond_to?(:service_url)

        blob.service.url(
          blob.key,
          expires_in: expires_in,
          filename: blob.filename,
          content_type: blob.content_type,
          disposition: "inline"
        )
      end

      def allowed_content_types
        types = ENV.fetch("UPLOAD_CONTENT_TYPES", "").split(",").map(&:strip).reject(&:empty?)
        return DEFAULT_CONTENT_TYPES if types.empty?

        types
      end

      def public_upload_url_expires_in
        configured_seconds = ENV["PUBLIC_UPLOAD_URL_EXPIRES_IN_SECONDS"]
        return default_public_upload_url_expires_in if configured_seconds.blank?

        seconds = Integer(configured_seconds)
        return default_public_upload_url_expires_in unless seconds.positive?

        seconds
      rescue ArgumentError
        default_public_upload_url_expires_in
      end

      def default_public_upload_url_expires_in
        seconds = ActiveStorage.service_urls_expire_in.to_i
        return DEFAULT_PUBLIC_UPLOAD_URL_EXPIRES_IN_SECONDS unless seconds.positive?

        seconds
      end

      def render_invalid_upload!(message, details: nil)
        log_upload(success: false, uploaded_file: params[:file], error_message: message)
        render_error(code: :invalid_upload, message: message, status: :unprocessable_entity, details: details)
      end

      def log_upload(success:, uploaded_file:, blob: nil, error: nil, error_message: nil)
        payload = {
          storefront_key: Current.storefront_key,
          filename: uploaded_file&.original_filename,
          byte_size: uploaded_file&.size,
          content_type: uploaded_file&.content_type,
          signed_id: blob&.signed_id,
          success: success
        }

        if error
          AppLogger.error(event: "uploads.create.failed", error: error, **payload)
        elsif error_message
          AppLogger.log(event: "uploads.create.rejected", level: :warn, error_message: error_message, **payload)
        else
          AppLogger.log(event: "uploads.create", **payload)
        end
      end
    end
  end
end

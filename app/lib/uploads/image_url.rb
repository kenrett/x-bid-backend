require "uri"

module Uploads
  module ImageUrl
    UPLOAD_PATH_PREFIX = "/api/v1/uploads/".freeze
    BLOB_KEY_PATTERN = /\A[a-zA-Z0-9\-_]{20,}\z/.freeze

    module_function

    def stable(raw_value)
      value = raw_value.to_s.strip
      return nil if value.empty?

      signed_id = extract_signed_id(value)
      return upload_path(signed_id) if signed_id.present?

      blob = blob_from_service_url(value)
      return value unless blob

      upload_path(blob.signed_id)
    end

    def upload_path(signed_id)
      "#{UPLOAD_PATH_PREFIX}#{signed_id}"
    end

    def extract_signed_id(value)
      return nil if value.blank?

      if value.start_with?(UPLOAD_PATH_PREFIX)
        signed_id = value.delete_prefix(UPLOAD_PATH_PREFIX)
        return signed_id if authorized_blob?(signed_id)
      end

      uri = parse_uri(value)
      if uri && uri.path.start_with?(UPLOAD_PATH_PREFIX)
        signed_id = uri.path.delete_prefix(UPLOAD_PATH_PREFIX)
        return signed_id if authorized_blob?(signed_id)
      end

      return value if authorized_blob?(value)

      nil
    end

    def blob_from_service_url(value)
      uri = parse_uri(value)
      return nil unless uri

      blob_key = extract_blob_key(uri.path.to_s)
      return nil if blob_key.blank?

      blob = ActiveStorage::Blob.find_by(key: blob_key)
      return nil unless blob
      return nil unless UploadAuthorization.exists?(blob_id: blob.id)

      blob
    end

    def extract_blob_key(path)
      segments = path.to_s.split("/").reject(&:blank?)
      return nil if segments.empty?
      return segments.first if segments.first.match?(BLOB_KEY_PATTERN)

      nil
    end

    def parse_uri(value)
      return URI.parse(value) if value.match?(/\Ahttps?:\/\//i)

      URI.parse(value.start_with?("/") ? value : "/#{value}")
    rescue URI::InvalidURIError
      nil
    end

    def authorized_blob?(signed_id)
      return false if signed_id.blank?

      blob = ActiveStorage::Blob.find_signed(signed_id)
      return false unless blob

      UploadAuthorization.exists?(blob_id: blob.id)
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      false
    end
  end
end

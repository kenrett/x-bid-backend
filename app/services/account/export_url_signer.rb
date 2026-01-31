require "active_support/message_verifier"
require "cgi"

module Account
  class ExportUrlSigner
    DEFAULT_TTL_SECONDS = 15.minutes.to_i

    def initialize(ttl_seconds: default_ttl_seconds, secret: Rails.application.secret_key_base)
      @ttl_seconds = ttl_seconds
      @verifier = ActiveSupport::MessageVerifier.new(secret, digest: "SHA256")
    end

    def signed_url_for(export)
      token = @verifier.generate(
        {
          export_id: export.id,
          user_id: export.user_id,
          exp: Time.current.to_i + @ttl_seconds
        },
        purpose: "account_export_download"
      )

      base_url = ENV.fetch("APP_URL", "http://localhost:3000").delete_suffix("/")
      "#{base_url}/api/v1/account/export/download?token=#{CGI.escape(token)}"
    end

    def verify!(token)
      payload = @verifier.verify(token.to_s, purpose: "account_export_download")
      exp = (payload[:exp] || payload["exp"]).to_i
      raise ArgumentError, "Token expired" if exp <= Time.current.to_i

      payload
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      raise ArgumentError, "Invalid token"
    end

    private

    def default_ttl_seconds
      value = ENV.fetch("ACCOUNT_EXPORT_URL_TTL_SECONDS", DEFAULT_TTL_SECONDS).to_i
      value.positive? ? value : DEFAULT_TTL_SECONDS
    end
  end
end

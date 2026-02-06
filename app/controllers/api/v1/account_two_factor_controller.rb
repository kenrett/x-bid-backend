require "rotp"

module Api
  module V1
    class AccountTwoFactorController < ApplicationController
      before_action :authenticate_request!
      rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing

      # GET /api/v1/account/2fa
      # @summary Return 2FA status for current account
      # @response Success (200) [AccountTwoFactorStatusResponse]
      # @response Unauthorized (401) [Error]
      def show
        render json: {
          enabled: @current_user.two_factor_enabled?,
          enabled_at: @current_user.two_factor_enabled_at&.iso8601
        }, status: :ok
      end

      # POST /api/v1/account/2fa/setup
      # @summary Start 2FA setup and return the provisioning URI
      # @response Success (200) [AccountTwoFactorSetupResponse]
      # @response Unauthorized (401) [Error]
      # @response Unprocessable content (422) [Error]
      def setup
        if @current_user.two_factor_enabled?
          return render_error(code: :two_factor_already_enabled, message: "Two-factor is already enabled", status: :unprocessable_content)
        end

        secret = ROTP::Base32.random
        @current_user.two_factor_secret = secret
        @current_user.save!

        AuditLogger.log(action: "account.2fa.setup", actor: @current_user, user: @current_user, request: request)

        render json: {
          secret: secret,
          otpauth_uri: @current_user.two_factor_provisioning_uri
        }, status: :ok
      end

      # POST /api/v1/account/2fa/verify
      # @summary Verify 2FA code and enable
      # @response Success (200) [AccountTwoFactorVerifyResponse]
      # @response Unauthorized (401) [Error]
      def verify
        code = two_factor_params.fetch(:code)

        unless @current_user.verify_two_factor_code(code)
          return render_error(code: :invalid_two_factor_code, message: "Invalid verification code", status: :unauthorized)
        end

        @current_user.update!(two_factor_enabled_at: Time.current)
        recovery_codes = @current_user.generate_two_factor_recovery_codes!
        @current_session_token&.update!(two_factor_verified_at: Time.current)

        AuditLogger.log(action: "account.2fa.enabled", actor: @current_user, user: @current_user, request: request)

        render json: { status: "enabled", recovery_codes: recovery_codes }, status: :ok
      end

      # POST /api/v1/account/2fa/disable
      # @summary Disable 2FA (requires password + code)
      # @response Success (200) [AccountTwoFactorDisableResponse]
      # @response Unauthorized (401) [Error]
      def disable
        password = two_factor_params.fetch(:current_password)
        code = two_factor_params.fetch(:code)

        unless @current_user.authenticate(password.to_s)
          return render_error(code: :invalid_password, message: "Invalid password", status: :unauthorized)
        end

        verified = @current_user.verify_two_factor_code(code) || @current_user.consume_recovery_code!(code)
        unless verified
          return render_error(code: :invalid_two_factor_code, message: "Invalid verification code", status: :unauthorized)
        end

        @current_user.clear_two_factor!
        AuditLogger.log(action: "account.2fa.disabled", actor: @current_user, user: @current_user, request: request)

        render json: { status: "disabled" }, status: :ok
      end

      private

      def two_factor_params
        (params[:account].presence || params).permit(:code, :current_password)
      end

      def handle_parameter_missing(exception)
        render_error(code: :bad_request, message: exception.message, status: :bad_request)
      end
    end
  end
end

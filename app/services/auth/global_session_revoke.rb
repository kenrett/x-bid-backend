module Auth
  class GlobalSessionRevoke
    DEFAULT_REASON = "incident_response".freeze
    SECRET_ROTATION_NOTE = "Rotate SECRET_KEY_BASE in Render and redeploy to invalidate signed cookies and bearer JWTs.".freeze

    def initialize(actor: nil, reason: nil, request: nil, rotate_signing_secrets: false, triggered_via: "unknown", triggered_by: nil)
      @actor = actor
      @reason = reason.to_s.strip.presence || DEFAULT_REASON
      @request = request
      @rotate_signing_secrets = ActiveModel::Type::Boolean.new.cast(rotate_signing_secrets)
      @triggered_via = triggered_via.to_s.presence || "unknown"
      @triggered_by = triggered_by.to_s.strip.presence || @actor&.email_address || "unknown"
    end

    def call
      revoked_at = Time.current
      revoked_count = SessionToken.active.update_all(revoked_at: revoked_at, updated_at: revoked_at)
      payload = build_payload(revoked_count: revoked_count, revoked_at: revoked_at)

      AuditLogger.log(
        action: "auth.sessions.global_revoke",
        actor: @actor,
        user: @actor,
        request: @request,
        payload: payload
      )
      AppLogger.log(
        event: "auth.sessions.global_revoke",
        actor_id: @actor&.id,
        actor_email: @actor&.email_address,
        reason: @reason,
        revoked_count: revoked_count,
        revoked_at: revoked_at.iso8601,
        triggered_via: @triggered_via,
        triggered_by: @triggered_by,
        rotate_signing_secrets: @rotate_signing_secrets
      )

      ServiceResult.ok(code: :revoked, data: payload.merge(revoked_at: revoked_at))
    rescue ActiveRecord::ActiveRecordError => e
      AppLogger.error(
        event: "auth.sessions.global_revoke.error",
        error: e,
        actor_id: @actor&.id,
        actor_email: @actor&.email_address,
        reason: @reason,
        triggered_via: @triggered_via,
        triggered_by: @triggered_by
      )
      ServiceResult.fail("Unable to revoke all sessions", code: :invalid_state)
    end

    private

    def build_payload(revoked_count:, revoked_at:)
      payload = {
        reason: @reason,
        revoked_count: revoked_count,
        revoked_at: revoked_at.iso8601,
        triggered_via: @triggered_via,
        triggered_by: @triggered_by,
        rotate_signing_secrets: @rotate_signing_secrets
      }

      payload[:secret_rotation_note] = SECRET_ROTATION_NOTE if @rotate_signing_secrets
      payload
    end
  end
end

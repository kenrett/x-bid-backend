require "json"

namespace :auth do
  namespace :sessions do
    desc "Emergency kill-switch: revoke all active sessions"
    task revoke_all: :environment do
      actor_email = ENV["ACTOR_EMAIL"].to_s.strip.downcase
      abort "ACTOR_EMAIL is required and must belong to a superadmin." if actor_email.blank?

      actor = User.find_by(email_address: actor_email)
      abort "No user found for ACTOR_EMAIL=#{actor_email.inspect}" unless actor
      abort "ACTOR_EMAIL must belong to a superadmin user." unless actor.superadmin?

      reason = ENV["REASON"].to_s.strip.presence || Auth::GlobalSessionRevoke::DEFAULT_REASON
      rotate_signing_secrets = ActiveModel::Type::Boolean.new.cast(ENV["ROTATE_SIGNING_SECRETS"])
      triggered_by = ENV["TRIGGERED_BY"].to_s.strip.presence || ENV["USER"].to_s.strip.presence || actor.email_address

      result = Auth::GlobalSessionRevoke.new(
        actor: actor,
        reason: reason,
        rotate_signing_secrets: rotate_signing_secrets,
        triggered_via: "rake",
        triggered_by: triggered_by
      ).call
      abort result.message unless result.ok?

      puts JSON.pretty_generate(
        status: "revoked",
        sessions_revoked: result[:revoked_count],
        revoked_at: result[:revoked_at]&.iso8601,
        reason: result[:reason],
        rotate_signing_secrets: result[:rotate_signing_secrets],
        secret_rotation_note: result[:secret_rotation_note],
        actor_id: actor.id,
        actor_email: actor.email_address,
        triggered_by: triggered_by
      )
    end
  end
end

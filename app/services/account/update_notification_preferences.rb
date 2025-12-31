module Account
  class UpdateNotificationPreferences
    def initialize(user:, preferences:)
      @user = user
      @preferences = preferences
    end

    def call
      return ServiceResult.fail("User required", code: :invalid_user) unless @user

      allowed = User::NOTIFICATION_PREFERENCE_DEFAULTS.keys.map(&:to_s)
      provided = @preferences.to_h.transform_keys(&:to_s)
      provided = coerce_boolean_values(provided)

      invalid_keys = provided.keys - allowed
      return ServiceResult.fail("Invalid notification preference key(s)", code: :validation_error, details: { allowed_keys: allowed, invalid_keys: invalid_keys }) if invalid_keys.any?

      non_boolean = provided.select { |_k, v| v != true && v != false }.keys
      return ServiceResult.fail("Notification preferences must be boolean", code: :validation_error, details: { non_boolean_keys: non_boolean }) if non_boolean.any?

      updated = @user.notification_preferences.to_h.merge(provided)
      @user.update!(notification_preferences: updated)

      ServiceResult.ok(code: :updated, data: { notification_preferences: @user.notification_preferences_with_defaults })
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.fail(e.record.errors.full_messages.to_sentence, code: :validation_error, record: e.record)
    end

    private

    def coerce_boolean_values(values)
      values.transform_values do |value|
        case value
        when true, false
          value
        when String
          normalized = value.strip.downcase
          if normalized == "true"
            true
          elsif normalized == "false"
            false
          else
            value
          end
        when Integer
          if value == 1
            true
          elsif value == 0
            false
          else
            value
          end
        else
          value
        end
      end
    end
  end
end

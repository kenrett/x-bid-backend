module Maintenance
  class Toggle
    def initialize(setting: MaintenanceSetting.global, cache: Rails.cache)
      @setting = setting
      @cache = cache
    end

    def update(enabled:)
      enabled_bool = ActiveRecord::Type::Boolean.new.cast(enabled)
      @setting.update!(enabled: enabled_bool)
      @cache.write(cache_key(:enabled), enabled_bool)
      @cache.write(cache_key(:updated_at), Time.current.iso8601)
      enabled_bool
    end

    def payload
      enabled = @cache.read(cache_key(:enabled))
      enabled = @setting.enabled if enabled.nil?
      {
        maintenance: {
          enabled: enabled,
          updated_at: @cache.read(cache_key(:updated_at)) || @setting.updated_at&.iso8601
        }
      }
    end

    private

    def cache_key(suffix)
      "maintenance_mode.#{suffix}"
    end
  end
end

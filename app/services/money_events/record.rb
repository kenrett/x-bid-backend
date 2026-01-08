module MoneyEvents
  class Record
    def self.call(...)
      new(...).call
    end

    def initialize(user:, event_type:, amount_cents:, currency:, occurred_at: Time.current, source: nil, source_type: nil, source_id: nil, metadata: nil, storefront_key: nil)
      @user = user
      @event_type = event_type
      @amount_cents = amount_cents
      @currency = currency
      @occurred_at = occurred_at
      @source = source
      @source_type = source_type
      @source_id = source_id
      @metadata = metadata
      @storefront_key = storefront_key
    end

    def call
      resolved_storefront_key =
        @storefront_key.to_s.presence ||
          (@source.respond_to?(:storefront_key) ? @source.storefront_key.to_s.presence : nil) ||
          Current.storefront_key.to_s.presence

      attrs = {
        user: @user,
        event_type: @event_type,
        amount_cents: @amount_cents,
        currency: @currency,
        occurred_at: @occurred_at,
        metadata: @metadata,
        storefront_key: resolved_storefront_key
      }

      if @source.present?
        attrs[:source] = @source
      else
        attrs[:source_type] = @source_type
        attrs[:source_id] = @source_id
      end

      MoneyEvent.create!(attrs)
    end
  end
end

module Auctions
  class Status
    EXTERNAL_TO_INTERNAL = {
      "inactive" => "inactive",
      "scheduled" => "pending",
      "active" => "active",
      "complete" => "ended",
      "cancelled" => "cancelled"
    }.freeze

    INTERNAL = %w[pending active ended cancelled inactive].freeze

    REVERSE = {
      "pending" => "scheduled",
      "ended" => "complete"
    }.freeze

    class << self
      def to_internal(value)
        return nil if value.blank?

        normalized = value.to_s.downcase
        return normalized if INTERNAL.include?(normalized)

        EXTERNAL_TO_INTERNAL[normalized]
      end

      def from_api(value)
        to_internal(value)
      end

      def to_api(enum_value)
        REVERSE.fetch(enum_value, enum_value)
      end

      def allowed_keys
        EXTERNAL_TO_INTERNAL.keys
      end
    end
  end
end

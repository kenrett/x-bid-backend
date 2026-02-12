module Auctions
  class Status
    ALLOWED = {
      "inactive" => "inactive",
      "scheduled" => "pending",
      "active" => "active",
      "complete" => "ended",
      "cancelled" => "cancelled"
    }.freeze

    REVERSE = {
      "pending" => "scheduled",
      "ended" => "complete"
    }.freeze

    class << self
      def from_api(value)
        return nil if value.blank?

        normalized = value.to_s.downcase
        return "pending" if normalized == "pending"
        return "ended" if normalized == "ended"

        ALLOWED[normalized]
      end

      def to_api(enum_value)
        REVERSE.fetch(enum_value, enum_value)
      end

      def allowed_keys
        ALLOWED.keys
      end
    end
  end
end

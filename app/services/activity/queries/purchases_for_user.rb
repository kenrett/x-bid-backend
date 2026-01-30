module Activity
  module Queries
    class PurchasesForUser
      Record = Struct.new(:purchase, :occurred_at, :money_event, keyword_init: true)

      attr_reader :records

      def self.call(user:, relation: nil)
        new(user: user, relation: relation).call
      end

      def initialize(user:, relation: nil)
        raise ArgumentError, "User must be provided" unless user

        @user = user
        @relation = relation
        @records = []
      end

      def call
        purchases = (relation || Purchase.all)
          .includes(:bid_pack)
          .where(user_id: user.id, status: %w[applied completed])
          .order(created_at: :desc, id: :desc)
          .to_a

        money_events_by_payment_intent = money_events_indexed_by_payment_intent_for(purchases)

        @records = purchases.map do |purchase|
          money_event = money_events_by_payment_intent[purchase.stripe_payment_intent_id.to_s]
          occurred_at = money_event&.occurred_at || purchase.created_at
          Record.new(purchase: purchase, occurred_at: occurred_at, money_event: money_event)
        end

        self
      end

      private

      attr_reader :user, :relation

      def money_events_indexed_by_payment_intent_for(purchases)
        ids = purchases.map(&:stripe_payment_intent_id).compact.uniq
        return {} if ids.empty?

        MoneyEvent
          .where(
            user_id: user.id,
            event_type: :purchase,
            source_type: "StripePaymentIntent",
            source_id: ids
          )
          .index_by { |event| event.source_id.to_s }
      end
    end
  end
end

module Credits
  module Ledger
    class Writer
      DEFAULT_KEY = StorefrontKeyable::DEFAULT_KEY
      CANONICAL_KEYS = StorefrontKeyable::CANONICAL_KEYS.freeze

      class Result
        attr_reader :transaction

        def initialize(transaction, existing: false)
          @transaction = transaction
          @existing = existing
        end

        def existing?
          @existing
        end

        def created?
          !existing?
        end
      end

      class << self
        def write!(
          user:,
          kind:,
          amount:,
          reason:,
          idempotency_key:,
          metadata: {},
          storefront_key: nil,
          purchase: nil,
          auction: nil,
          admin_actor: nil,
          stripe_event: nil,
          stripe_payment_intent_id: nil,
          stripe_checkout_session_id: nil,
          entry_type: nil
        )
          raise ArgumentError, "User must be provided" unless user
          raise ArgumentError, "Kind must be provided" if kind.blank?
          raise ArgumentError, "Reason must be provided" if reason.blank?
          raise ArgumentError, "Idempotency key must be provided" if idempotency_key.blank?

          sanitized_entry_type = (entry_type.presence || reason).to_s
          resolved_storefront_key = resolve_storefront_key!(storefront_key, sanitized_entry_type, user.id, amount)
          ensure_allowed_storefront!(resolved_storefront_key)

          existing = CreditTransaction.find_by(idempotency_key: idempotency_key)
          return Result.new(existing, existing: true) if existing

          transaction = create_transaction(
            user: user,
            kind: kind,
            amount: amount,
            reason: reason,
            idempotency_key: idempotency_key,
            metadata: metadata,
            storefront_key: resolved_storefront_key,
            purchase: purchase,
            auction: auction,
            admin_actor: admin_actor,
            stripe_event: stripe_event,
            stripe_payment_intent_id: stripe_payment_intent_id,
            stripe_checkout_session_id: stripe_checkout_session_id
          )

          log_entry_created(
            transaction: transaction,
            entry_type: sanitized_entry_type,
            amount: amount,
            storefront_key: resolved_storefront_key
          )

          Result.new(transaction)
        rescue ActiveRecord::RecordNotUnique
          existing = CreditTransaction.find_by!(idempotency_key: idempotency_key)
          ensure_same_user!(existing, user)

          Result.new(existing, existing: true)
        end

        private

        def create_transaction(
          user:,
          kind:,
          amount:,
          reason:,
          idempotency_key:,
          metadata:,
          storefront_key:,
          purchase:,
          auction:,
          admin_actor:,
          stripe_event:,
          stripe_payment_intent_id:,
          stripe_checkout_session_id:
        )
          CreditTransaction.create!(
            user: user,
            kind: kind,
            amount: amount,
            reason: reason,
            idempotency_key: idempotency_key,
            metadata: metadata || {},
            storefront_key: storefront_key,
            purchase: purchase,
            auction: auction,
            admin_actor: admin_actor,
            stripe_event: stripe_event,
            stripe_payment_intent_id: stripe_payment_intent_id,
            stripe_checkout_session_id: stripe_checkout_session_id
          )
        end

        def resolve_storefront_key!(provided, entry_type, user_id, amount)
          candidate = provided.to_s.presence || Current.storefront_key.to_s.presence
          return candidate if candidate.present?

          AppLogger.log(
            event: "ledger.write.missing_storefront",
            level: :warn,
            defaulted_to: DEFAULT_KEY,
            entry_type: entry_type,
            user_id: user_id,
            amount: amount,
            request_id: Current.request_id
          )

          DEFAULT_KEY
        end

        def ensure_allowed_storefront!(storefront_key)
          return if CANONICAL_KEYS.include?(storefront_key)

          raise ArgumentError, "Invalid storefront_key: #{storefront_key.inspect}"
        end

        def ensure_same_user!(existing, user)
          return if existing.user_id == user.id

          raise ArgumentError, "Idempotency key belongs to a different user"
        end

        def log_entry_created(transaction:, entry_type:, amount:, storefront_key:)
          AppLogger.log(
            event: "ledger.entry.created",
            storefront_key: storefront_key,
            entry_type: entry_type,
            amount: amount,
            user_id: transaction.user_id,
            idempotency_key: transaction.idempotency_key,
            request_id: Current.request_id,
            credit_transaction_id: transaction.id
          )
        end
      end
    end
  end
end

module Account
  class ExportPayload
    def initialize(user:)
      @user = user
    end

    def call
      {
        user: user_payload,
        purchases: purchases_payload,
        bids: bids_payload,
        auction_watches: watches_payload,
        ledger_entries: ledger_entries_payload,
        bids_count: @user.bids.count,
        auction_watches_count: @user.auction_watches.count,
        notifications_count: @user.notifications.count
      }
    end

    private

    attr_reader :user

    def user_payload
      {
        id: user.id,
        name: user.name,
        email_address: user.email_address,
        email_verified_at: user.email_verified_at&.iso8601,
        created_at: user.created_at.iso8601,
        role: user.role,
        status: user.status
      }
    end

    def purchases_payload
      user.purchases.includes(:bid_pack).order(created_at: :desc).map do |purchase|
        {
          id: purchase.id,
          bid_pack: {
            id: purchase.bid_pack_id,
            name: purchase.bid_pack&.name
          },
          amount_cents: purchase.amount_cents,
          currency: purchase.currency,
          status: purchase.status,
          stripe_payment_intent_id: purchase.stripe_payment_intent_id,
          stripe_checkout_session_id: purchase.stripe_checkout_session_id,
          created_at: purchase.created_at.iso8601
        }
      end
    end

    def bids_payload
      user.bids.includes(:auction).order(created_at: :desc).map do |bid|
        {
          id: bid.id,
          auction: {
            id: bid.auction_id,
            title: bid.auction&.title
          },
          amount: bid.amount,
          created_at: bid.created_at.iso8601
        }
      end
    end

    def watches_payload
      user.auction_watches.includes(:auction).order(created_at: :desc).map do |watch|
        {
          id: watch.id,
          auction: {
            id: watch.auction_id,
            title: watch.auction&.title
          },
          created_at: watch.created_at.iso8601
        }
      end
    end

    def ledger_entries_payload
      CreditTransaction.where(user_id: user.id).order(created_at: :desc).map do |entry|
        {
          id: entry.id,
          kind: entry.kind,
          amount: entry.amount,
          reason: entry.reason,
          purchase_id: entry.purchase_id,
          auction_id: entry.auction_id,
          idempotency_key: entry.idempotency_key,
          created_at: entry.created_at.iso8601,
          metadata: entry.metadata
        }
      end
    end
  end
end

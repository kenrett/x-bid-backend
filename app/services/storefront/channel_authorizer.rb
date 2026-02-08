module Storefront
  class ChannelAuthorizer
    def self.can_subscribe_to_auction?(auction:, storefront_key:, session_token:)
      new(
        auction: auction,
        storefront_key: storefront_key,
        session_token: session_token
      ).can_subscribe_to_auction?
    end

    def initialize(auction:, storefront_key:, session_token:)
      @auction = auction
      @storefront_key = storefront_key.to_s.presence || StorefrontKeyable::DEFAULT_KEY
      @session_token = session_token
    end

    def can_subscribe_to_auction?
      return false unless auction
      return false unless within_storefront_scope?
      return true unless Storefront::Policy.adult_detail?(auction)

      Storefront::Policy.can_view_adult_detail?(
        storefront_key: storefront_key,
        session_token: session_token,
        auction: auction
      )
    end

    private

    attr_reader :auction, :storefront_key, :session_token

    def within_storefront_scope?
      scoped = Storefront::Policy.scope_auctions(
        relation: Auction.where(id: auction.id),
        storefront_key: storefront_key
      )
      scoped.exists?
    end
  end
end

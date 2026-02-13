class AuctionChannel < ApplicationCable::Channel
  LIST_STREAM_PREFIX = "AuctionChannel:list".freeze

  def self.list_stream_for(storefront_key)
    key = storefront_key.to_s.presence || StorefrontKeyable::DEFAULT_KEY
    "#{LIST_STREAM_PREFIX}:#{key}"
  end

  def subscribed
    return subscribe_to_list if params[:stream] == "list"

    subscribe_to_auction
  end

  # Called when a consumer unsubscribes from the channel.
  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end

  # This action is called by the client just before making a bid via HTTP.
  # It temporarily stops this connection from receiving broadcasts for this auction,
  # preventing the user from receiving an echo of their own bid.
  def stop_stream
    stop_stream_for @auction if @auction
  end

  # This action can be called by the client after a bid is placed to resume
  # receiving broadcasts for this auction.
  def start_stream
    stream_for @auction if @auction
  end

  private

  def subscribe_to_list
    if list_subscription_requires_age_verification? && !age_verified_session?
      return reject_with_reason("age_gate_required")
    end

    stream_from list_stream
  end

  def subscribe_to_auction
    auction_id = params[:auction_id]

    return reject_with_reason("missing_auction_id") if auction_id.blank?

    @auction = Auction.find_by(id: auction_id)
    return reject_with_reason("auction_not_found", auction_id: auction_id) unless @auction

    unless allowed_to_stream_auction?(@auction)
      return reject_with_reason(
        "auction_out_of_scope",
        auction_id: auction_id
      )
    end

    stream_for @auction
  end

  def allowed_to_stream_auction?(auction)
    Storefront::ChannelAuthorizer.can_subscribe_to_auction?(
      auction: auction,
      storefront_key: storefront_key,
      session_token: connection.current_session_token
    )
  end

  def list_stream
    self.class.list_stream_for(storefront_key)
  end

  def storefront_key
    connection.current_storefront_key.to_s.presence || StorefrontKeyable::DEFAULT_KEY
  end

  def list_subscription_requires_age_verification?
    Storefront::Capabilities.requires_age_gate?(storefront_key)
  end

  def age_verified_session?
    token = connection.current_session_token
    token&.respond_to?(:age_verified_at) && token.age_verified_at.present?
  end

  def reject_with_reason(reason, **context)
    AppLogger.log(
      event: "auction_channel.subscription_rejected",
      level: :warn,
      reason: reason,
      storefront_key: storefront_key,
      **context
    )
    reject
  end
end

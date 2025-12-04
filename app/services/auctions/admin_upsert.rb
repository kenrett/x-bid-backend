class Auctions::AdminUpsert
  Result = Struct.new(:record, :error, keyword_init: true)

  def initialize(actor:, auction: nil, attrs:, request: nil)
    @actor = actor
    @auction = auction || Auction.new
    @attrs = attrs
    @request = request
  end

  def call
    if @auction.update(@attrs)
      AuditLogger.log(action: action_name, actor: @actor, target: @auction, payload: @attrs, request: request_context)
      Result.new(record: @auction)
    else
      Result.new(error: @auction.errors.full_messages.to_sentence)
    end
  end

  private

  def action_name
    @auction.persisted? ? "auction.update" : "auction.create"
  end

  def request_context
    @request
  end
end

class Auctions::Retire
  Result = Struct.new(:success, :error, keyword_init: true)

  def initialize(actor:, auction:, request: nil)
    @actor = actor
    @auction = auction
    @request = request
  end

  def call
    return Result.new(error: "Auction already inactive") if @auction.inactive?
    return Result.new(error: "Cannot retire an auction that has bids.") if @auction.bids.exists?

    if @auction.update(status: :inactive)
      AuditLogger.log(action: "auction.delete", actor: @actor, target: @auction, payload: { status: "inactive" }, request: @request)
      Result.new(success: true)
    else
      Result.new(error: @auction.errors.full_messages.to_sentence)
    end
  end
end

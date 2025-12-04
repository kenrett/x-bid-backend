class Auctions::AdminUpsert
  def initialize(actor:, auction: nil, attrs:, request: nil)
    @actor = actor
    @auction = auction || Auction.new
    @attrs = normalize_status(attrs)
    @request = request
  end

  def call
    if @auction.update(@attrs)
      AuditLogger.log(action: action_name, actor: @actor, target: @auction, payload: @attrs, request: request_context)
      ServiceResult.ok(record: @auction)
    else
      ServiceResult.fail(@auction.errors.full_messages.to_sentence)
    end
  end

  private

  def action_name
    @auction.persisted? ? "auction.update" : "auction.create"
  end

  def request_context
    @request
  end

  def normalize_status(attrs)
    return attrs unless attrs.respond_to?(:to_h)
    hash = attrs.to_h
    return hash unless hash.key?("status") || hash.key?(:status)

    key = hash.key?("status") ? "status" : :status
    mapped = Auctions::Status.from_api(hash[key])
    mapped ? hash.merge(key => mapped) : hash
  end
end

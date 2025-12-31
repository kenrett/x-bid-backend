class ServiceResult
  attr_reader :code, :message, :data, :record

  HTTP_STATUS_BY_CODE = {
    forbidden: :forbidden,
    not_found: :not_found,
    rate_limited: :too_many_requests,
    invalid_state: :unprocessable_content,
    invalid_status: :unprocessable_content,
    invalid_auction: :unprocessable_content,
    invalid_bid_pack: :unprocessable_content,
    invalid_delta: :unprocessable_content,
    invalid_user: :unprocessable_content,
    insufficient_credits: :unprocessable_content,
    invalid_amount: :unprocessable_content,
    amount_exceeds_charge: :unprocessable_content,
    gateway_error: :unprocessable_content,
    already_refunded: :unprocessable_content,
    missing_payment_reference: :unprocessable_content,
    invalid_address: :unprocessable_content
  }.freeze

  def initialize(success:, code: nil, message: nil, data: {}, record: nil, metadata: {})
    @success = !!success
    @code = code
    @message = message&.to_s
    @data = data || {}
    @record = record
    @metadata = metadata || {}
  end

  def self.ok(code: :ok, message: nil, data: {}, record: nil, **metadata)
    new(success: true, code: code, message: message, data: data, record: record, metadata: metadata)
  end

  def self.fail(message, code: :error, data: {}, record: nil, **metadata)
    new(success: false, code: code, message: message, data: data, record: record, metadata: metadata)
  end

  def ok? = @success
  alias_method :success?, :ok?

  def error
    ok? ? nil : @message
  end

  def [](key)
    return record if key == :record
    return data[key] if data.is_a?(Hash) && data.key?(key)

    @metadata[key]
  end

  def method_missing(method_name, *args, &block)
    return data[method_name] if data.respond_to?(:key?) && data.key?(method_name)
    return @metadata[method_name] if @metadata.key?(method_name)

    super
  end

  def respond_to_missing?(method_name, include_private = false)
    (data.respond_to?(:key?) && data.key?(method_name)) || @metadata.key?(method_name) || super
  end

  def http_status(success_status: :ok, fallback: :unprocessable_content)
    return success_status if ok?

    HTTP_STATUS_BY_CODE.fetch(code&.to_sym, fallback)
  end
end

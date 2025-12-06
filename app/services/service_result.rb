class ServiceResult
  attr_reader :error, :payload, :code

  def initialize(success:, error: nil, code: nil, payload: {})
    @success = success
    @error = error
    @code = code
    @payload = payload || {}
  end

  def self.ok(payload = {})
    new(success: true, payload: payload)
  end

  def self.fail(error, code: nil)
    new(success: false, error: error, code: code, payload: {})
  end

  def success?
    @success
  end

  def [](key)
    payload[key]
  end

  def method_missing(method_name, *args, &block)
    return payload[method_name] if payload.key?(method_name)

    super
  end

  def respond_to_missing?(method_name, include_private = false)
    payload.key?(method_name) || super
  end
end

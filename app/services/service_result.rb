class ServiceResult
  attr_reader :code, :message, :data, :record

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
end

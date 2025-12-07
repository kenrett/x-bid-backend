class ServiceResult
  attr_reader :code, :error, :record

  def initialize(success:, error: nil, code: nil, record: nil, metadata: {})
    @success = !!success
    @error = error&.to_s
    @code = code
    @record = record
    @metadata = metadata || {}
  end

  def self.ok(record: nil, code: nil, **metadata)
    new(success: true, record: record, code: code, metadata: metadata)
  end

  def self.fail(error, code: :error, record: nil, **metadata)
    new(success: false, error: error, code: code, record: record, metadata: metadata)
  end

  def ok? = @success
  alias_method :success?, :ok?

  def [](key)
    return record if key == :record

    @metadata[key]
  end

  def method_missing(method_name, *args, &block)
    return @metadata[method_name] if @metadata.key?(method_name)

    super
  end

  def respond_to_missing?(method_name, include_private = false)
    @metadata.key?(method_name) || super
  end
end

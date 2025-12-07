require "test_helper"

class ServiceResultTest < ActiveSupport::TestCase
  test ".ok returns a successful result" do
    record = Object.new

    result = ServiceResult.ok(record: record, code: :created)

    assert result.ok?
    assert result.success?
    assert_equal :created, result.code
    assert_equal record, result.record
  end

  test ".fail returns a failure result" do
    record = Object.new

    result = ServiceResult.fail("Invalid state", code: :invalid_state, record: record)

    assert_not result.ok?
    assert_not result.success?
    assert_equal "Invalid state", result.error
    assert_equal :invalid_state, result.code
    assert_equal record, result.record
  end

  test ".fail defaults the code to :error" do
    result = ServiceResult.fail("No code provided")

    assert_equal :error, result.code
  end
end

require "test_helper"

class SignupContractTest < ActionDispatch::IntegrationTest
  test "POST /api/v1/users returns the session-based signup contract (legacy alias)" do
    post "/api/v1/users", params: {
      user: {
        name: "User",
        email_address: "legacy_signup_contract@example.com",
        password: "password",
        password_confirmation: "password"
      }
    }

    assert_response :created
    body = JSON.parse(response.body)

    assert_exact_keys!(
      body,
      %w[token refresh_token session session_token_id is_admin is_superuser redirect_path user],
      label: "POST /api/v1/users response"
    )
  end

  test "POST /api/v1/signup returns the session-based signup contract (login-equivalent)" do
    post "/api/v1/signup", params: {
      user: {
        name: "User",
        email_address: "signup_contract@example.com",
        password: "password",
        password_confirmation: "password"
      }
    }

    assert_response :success
    body = JSON.parse(response.body)

    assert_exact_keys!(
      body,
      %w[token refresh_token session session_token_id is_admin is_superuser redirect_path user],
      label: "POST /api/v1/signup response"
    )
  end

  private

  def assert_exact_keys!(hash, expected_keys, label:)
    actual_keys = hash.keys.map(&:to_s).sort
    expected_keys = expected_keys.map(&:to_s).sort

    extra = actual_keys - expected_keys
    missing = expected_keys - actual_keys

    assert_equal(
      expected_keys,
      actual_keys,
      "#{label} keys mismatch.\nExpected: #{expected_keys}\nActual:   #{actual_keys}\nMissing:  #{missing}\nExtra:    #{extra}"
    )
  end
end

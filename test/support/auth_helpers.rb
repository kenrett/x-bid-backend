require "securerandom"
require "jwt"

module AuthHelpers
  # Example:
  #   actor = create_actor(role: :admin)
  #   get "/api/v1/admin/audit", headers: auth_headers_for(actor)
  #   assert_forbidden(response)
  #
  def create_actor(role:)
    role = role.to_sym
    unless User.roles.key?(role.to_s)
      raise ArgumentError, "Unknown role: #{role.inspect} (expected one of: #{User.roles.keys.join(", ")})"
    end

    unique = SecureRandom.hex(8)
    User.create!(
      name: "#{role}-#{unique}",
      email_address: "#{role}-#{unique}@example.com",
      password: "password",
      role: role,
      bid_credits: 0
    )
  end

  def auth_headers_for(actor, expires_at: 1.hour.from_now)
    session_token = SessionToken.create!(
      user: actor,
      token_digest: SessionToken.digest(SecureRandom.hex(32)),
      expires_at: expires_at
    )

    payload = { user_id: actor.id, session_token_id: session_token.id, exp: expires_at.to_i }
    jwt = encode_jwt(payload)

    { "Authorization" => "Bearer #{jwt}" }
  end

  def encode_jwt(payload, issued_at: Time.current)
    issued_at_i = issued_at.to_i
    normalized = payload.merge(
      iat: payload[:iat] || payload["iat"] || issued_at_i,
      nbf: payload[:nbf] || payload["nbf"] || issued_at_i
    )
    JWT.encode(normalized, Rails.application.secret_key_base, "HS256")
  end

  def csrf_headers(origin: nil)
    headers = {}
    headers["Origin"] = origin if origin.present?
    get "/api/v1/csrf", headers: headers
    assert_response :success
    token = JSON.parse(response.body).fetch("csrf_token")
    headers["X-CSRF-Token"] = token
    headers
  end

  def assert_forbidden(test_response = response)
    assert_equal 403, test_response.status, "Expected 403 Forbidden, got #{test_response.status}.\nBody: #{test_response.body}"
  end

  def assert_unauthorized(test_response = response)
    assert_equal 401, test_response.status, "Expected 401 Unauthorized, got #{test_response.status}.\nBody: #{test_response.body}"
  end
end

require "test_helper"

class SessionTokenDecoderTest < ActiveSupport::TestCase
  test "decodes freshly encoded token with iat/nbf" do
    user = User.create!(
      name: "Decoder User",
      email_address: "decoder-user@example.com",
      password: "password",
      bid_credits: 0
    )
    session_token = SessionToken.create!(
      user: user,
      token_digest: SessionToken.digest(SecureRandom.hex(32)),
      expires_at: 1.hour.from_now
    )

    token = ApplicationController.new.send(
      :encode_jwt,
      { user_id: user.id, session_token_id: session_token.id },
      expires_at: session_token.expires_at
    )

    decoded = Auth::SessionTokenDecoder.session_token_from_jwt(token)
    assert_equal session_token.id, decoded.id
  end

  test "missing iat/nbf claims fails decoding" do
    user = User.create!(
      name: "Decoder Missing Claims",
      email_address: "decoder-missing@example.com",
      password: "password",
      bid_credits: 0
    )
    session_token = SessionToken.create!(
      user: user,
      token_digest: SessionToken.digest(SecureRandom.hex(32)),
      expires_at: 1.hour.from_now
    )

    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = JWT.encode(payload, Rails.application.secret_key_base, "HS256")

    assert_raises(JWT::MissingRequiredClaim) do
      Auth::SessionTokenDecoder.session_token_from_jwt(token)
    end
  end
end

require "test_helper"
require "jwt"
require "securerandom"

class AccountManagementApiTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  DEFAULT_PREFS = User::NOTIFICATION_PREFERENCE_DEFAULTS.transform_keys(&:to_s).freeze

  def setup
    ActionMailer::Base.deliveries.clear
    @user = User.create!(name: "User", email_address: "user@example.com", password: "password", bid_credits: 0)
  end

  test "GET /api/v1/account returns profile + default notification preferences" do
    session_token = create_session_token_for(@user)

    get "/api/v1/account", headers: auth_headers(@user, session_token)
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal @user.id, body.dig("user", "id")
    assert_equal @user.email_address, body.dig("user", "email_address")
    assert_equal false, body.dig("user", "email_verified")
    assert_equal DEFAULT_PREFS, body.dig("user", "notification_preferences")
  end

  test "authenticated requests update current session last_seen_at (debounced)" do
    session_token = create_session_token_for(@user)
    session_token.update!(last_seen_at: 2.hours.ago)

    t1 = Time.current.change(usec: 0)
    travel_to(t1)
    begin
      get "/api/v1/account", headers: auth_headers(@user, session_token)
      assert_response :success
      first_seen = session_token.reload.last_seen_at
      assert_in_delta t1.to_i, first_seen.to_i, 1

      t2 = t1 + 2.seconds
      travel_to(t2)

      get "/api/v1/account", headers: auth_headers(@user, session_token)
      assert_response :success
      second_seen = session_token.reload.last_seen_at
      assert_equal first_seen.to_i, second_seen.to_i

      t3 = t1 + 61.seconds
      travel_to(t3)

      get "/api/v1/account", headers: auth_headers(@user, session_token)
      assert_response :success
      third_seen = session_token.reload.last_seen_at
      assert_operator third_seen, :>, second_seen
    ensure
      travel_back
    end
  end

  test "PATCH /api/v1/account updates name only" do
    session_token = create_session_token_for(@user)

    patch "/api/v1/account", params: { account: { name: "New Name" } }, headers: auth_headers(@user, session_token)
    assert_response :success
    assert_equal "New Name", @user.reload.name
  end

  test "POST /api/v1/account/password requires current password and revokes other sessions" do
    current_session = create_session_token_for(@user)
    other_session = create_session_token_for(@user)

    post "/api/v1/account/password",
      params: { current_password: "wrong", new_password: "newpassword" },
      headers: auth_headers(@user, current_session)
    assert_response :unprocessable_content
    body = JSON.parse(response.body)
    assert_equal "invalid_password", body.dig("error", "code").to_s

    audit_events = []
    AppLogger.stub(:log, lambda { |event:, level: :info, **context|
      audit_events << { event: event, level: level, **context }
    }) do
      post "/api/v1/account/password",
        params: { current_password: "password", new_password: "newpassword" },
        headers: auth_headers(@user, current_session)
    end
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "password_updated", body["status"]
    assert_equal 1, body["sessions_revoked"]
    assert other_session.reload.revoked_at.present?
    assert_nil current_session.reload.revoked_at
    assert audit_events.any? { |e| e[:event] == "account.password_change.succeeded" }
    assert audit_events.any? { |e| e[:event] == "account.session.revoked" && e[:reason] == "password_change" }
  end

  test "POST /api/v1/account/email/change sends verification and applies pending email on verify" do
    session_token = create_session_token_for(@user)

    perform_enqueued_jobs do
      post "/api/v1/account/email-change",
        params: { new_email_address: "new@example.com", current_password: "password" },
        headers: auth_headers(@user, session_token)
    end

    assert_response :accepted
    @user.reload
    assert_equal "new@example.com", @user.unverified_email_address
    assert @user.email_verification_token_digest.present?
    assert @user.email_verification_sent_at.present?

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "new@example.com" ], mail.to
    token = extract_token_from_email(mail)
    assert token.present?

    get "/api/v1/email_verifications/verify", params: { token: token }
    assert_response :success
    assert_equal "verified", JSON.parse(response.body)["status"]

    @user.reload
    assert_equal "new@example.com", @user.email_address
    assert @user.email_verified_at.present?
    assert_nil @user.unverified_email_address
    assert_nil @user.email_verification_token_digest
  end

  test "GET /api/v1/email_verifications/verify rejects expired tokens" do
    raw = SecureRandom.hex(32)
    @user.update!(
      unverified_email_address: "later@example.com",
      email_verification_token_digest: Auth::TokenDigest.digest(raw),
      email_verification_sent_at: 2.days.ago
    )

    get "/api/v1/email_verifications/verify", params: { token: raw }
    assert_response :unprocessable_content
    body = JSON.parse(response.body)
    assert_equal "invalid_token", body.dig("error", "code").to_s
  end

  test "POST /api/v1/email_verifications/resend enforces cooldown" do
    session_token = create_session_token_for(@user)

    perform_enqueued_jobs do
      post "/api/v1/account/email-change",
        params: { new_email_address: "cooldown@example.com", current_password: "password" },
        headers: auth_headers(@user, session_token)
    end
    assert_response :accepted

    post "/api/v1/email_verifications/resend", headers: auth_headers(@user, session_token)
    assert_response :too_many_requests
    body = JSON.parse(response.body)
    assert_equal "rate_limited", body.dig("error", "code").to_s

    travel 61.seconds do
      perform_enqueued_jobs do
        post "/api/v1/email_verifications/resend", headers: auth_headers(@user, session_token)
      end
      assert_response :accepted
    end
  end

  test "PUT /api/v1/account/notifications validates allowed keys and boolean values" do
    session_token = create_session_token_for(@user)

    put "/api/v1/account/notifications",
      params: { account: { notification_preferences: { "unknown" => true } } },
      headers: auth_headers(@user, session_token)
    assert_response :unprocessable_content
    body = JSON.parse(response.body)
    assert_equal "validation_error", body.dig("error", "code").to_s
    assert body.dig("error", "details", "allowed_keys").is_a?(Array)

    put "/api/v1/account/notifications",
      params: { account: { notification_preferences: { marketing_emails: true } } },
      headers: auth_headers(@user, session_token)
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal true, body.dig("notification_preferences", "marketing_emails")
  end

  test "GET/DELETE /api/v1/account/sessions lists and revokes sessions" do
    current_session = create_session_token_for(@user, user_agent: "UA-1", ip_address: "1.2.3.4")
    other_session = create_session_token_for(@user, user_agent: "UA-2", ip_address: "2.3.4.5")

    get "/api/v1/account/sessions", headers: auth_headers(@user, current_session)
    assert_response :success
    sessions = JSON.parse(response.body).fetch("sessions")
    assert_equal 2, sessions.size
    current = sessions.find { |s| s["id"] == current_session.id }
    assert_equal true, current["current"]

    audit_events = []
    AppLogger.stub(:log, lambda { |event:, level: :info, **context|
      audit_events << { event: event, level: level, **context }
    }) do
      delete "/api/v1/account/sessions/#{other_session.id}", headers: auth_headers(@user, current_session)
    end
    assert_response :success
    assert other_session.reload.revoked_at.present?
    assert audit_events.any? { |e| e[:event] == "account.session.revoked" && e[:reason] == "user_revoked" }

    delete "/api/v1/account/sessions/#{current_session.id}", headers: auth_headers(@user, current_session)
    assert_response :success
    assert current_session.reload.revoked_at.present?

    get "/api/v1/account", headers: auth_headers(@user, current_session)
    assert_response :unauthorized
  end

  test "DELETE /api/v1/account/sessions revokes all but current" do
    current_session = create_session_token_for(@user)
    other_session = create_session_token_for(@user)

    audit_events = []
    AppLogger.stub(:log, lambda { |event:, level: :info, **context|
      audit_events << { event: event, level: level, **context }
    }) do
      delete "/api/v1/account/sessions", headers: auth_headers(@user, current_session)
    end
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "revoked", body["status"]
    assert_equal 1, body["sessions_revoked"]
    assert other_session.reload.revoked_at.present?
    assert_nil current_session.reload.revoked_at
    assert audit_events.any? { |e| e[:event] == "account.session.revoked" && e[:reason] == "revoke_others" }
    assert audit_events.any? { |e| e[:event] == "account.sessions.revoked_others" && e[:sessions_revoked] == 1 }
  end

  test "DELETE /api/v1/account disables user, revokes sessions, and blocks login" do
    session_token = create_session_token_for(@user)
    other_session = create_session_token_for(@user)

    delete "/api/v1/account",
      params: { current_password: "password", confirmation: "DELETE" },
      headers: auth_headers(@user, session_token)
    assert_response :success
    assert_equal "deleted", JSON.parse(response.body)["status"]

    @user.reload
    assert @user.disabled?
    assert @user.disabled_at.present?
    assert session_token.reload.revoked_at.present?
    assert other_session.reload.revoked_at.present?

    post "/api/v1/login", params: { session: { email_address: "user@example.com", password: "password" } }
    assert_response :unauthorized
    assert_equal "invalid_credentials", JSON.parse(response.body).dig("error", "code").to_s
  end

  test "POST/GET /api/v1/account/export creates and returns latest export" do
    session_token = create_session_token_for(@user)

    post "/api/v1/account/export", headers: auth_headers(@user, session_token)
    assert_response :accepted
    export = JSON.parse(response.body).fetch("export")
    assert_includes %w[pending ready], export["status"]

    get "/api/v1/account/export", headers: auth_headers(@user, session_token)
    assert_response :success
    latest = JSON.parse(response.body).fetch("export")
    assert_equal export["id"], latest["id"]
  end

  test "GET /api/v1/account/security returns email verification security fields" do
    session_token = create_session_token_for(@user)

    get "/api/v1/account/security", headers: auth_headers(@user, session_token)
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal @user.email_address, body.dig("security", "email_address")
    assert_equal false, body.dig("security", "email_verified")
    assert_nil body.dig("security", "email_verified_at")
  end

  private

  def create_session_token_for(user, user_agent: nil, ip_address: nil)
    SessionToken.create!(
      user: user,
      token_digest: SessionToken.digest(SecureRandom.hex(32)),
      expires_at: 1.hour.from_now,
      user_agent: user_agent,
      ip_address: ip_address,
      last_seen_at: Time.current
    )
  end

  def auth_headers(user, session_token)
    payload = { user_id: user.id, session_token_id: session_token.id, exp: 1.hour.from_now.to_i }
    token = encode_jwt(payload)
    { "Authorization" => "Bearer #{token}" }
  end

  def extract_token_from_email(mail)
    bodies =
      if mail.multipart?
        mail.parts.map { |part| part.body.decoded.to_s }
      else
        [ mail.body.decoded.to_s ]
      end

    flattened = bodies.join("\n").gsub(/\s+/, "")
    match = flattened.match(/token(?:=|=3D)([0-9a-f]{64})/i)
    match&.captures&.first
  end
end

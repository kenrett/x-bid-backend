require "test_helper"

class SessionTokenTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  test "active? expires at the absolute deadline even if expires_at is still in the future" do
    with_session_ttls(idle_minutes: 30, absolute_minutes: 60) do
      user = create_actor(role: :user)
      t0 = Time.current.change(usec: 0)

      travel_to(t0) do
        token = SessionToken.create!(
          user: user,
          token_digest: SessionToken.digest(SecureRandom.hex(32)),
          expires_at: t0 + 2.hours
        )

        assert token.active?(now: t0 + 59.minutes)
        refute token.active?(now: t0 + 60.minutes)
      end
    end
  end

  test "active scope excludes tokens beyond the absolute deadline" do
    with_session_ttls(idle_minutes: 30, absolute_minutes: 60) do
      user = create_actor(role: :user)
      t0 = Time.current.change(usec: 0)
      stale_token = nil
      fresh_token = nil

      travel_to(t0 - 2.hours) do
        stale_token = SessionToken.create!(
          user: user,
          token_digest: SessionToken.digest(SecureRandom.hex(32)),
          expires_at: t0 + 2.hours
        )
      end

      travel_to(t0) do
        fresh_token = SessionToken.create!(
          user: user,
          token_digest: SessionToken.digest(SecureRandom.hex(32)),
          expires_at: t0 + 2.hours
        )

        active_ids = SessionToken.active.pluck(:id)
        assert_includes active_ids, fresh_token.id
        refute_includes active_ids, stale_token.id
      end
    end
  end

  test "sliding_expires_at is capped by the absolute deadline" do
    with_session_ttls(idle_minutes: 30, absolute_minutes: 90) do
      user = create_actor(role: :user)
      t0 = Time.current.change(usec: 0)

      travel_to(t0) do
        token = SessionToken.create!(
          user: user,
          token_digest: SessionToken.digest(SecureRandom.hex(32)),
          expires_at: t0 + 30.minutes
        )

        assert_in_delta (t0 + 70.minutes).to_i, token.sliding_expires_at(now: t0 + 40.minutes).to_i, 1
        assert_in_delta (t0 + 90.minutes).to_i, token.sliding_expires_at(now: t0 + 80.minutes).to_i, 1
      end
    end
  end

  private

  def with_session_ttls(idle_minutes:, absolute_minutes:)
    previous_idle = Rails.configuration.x.session_token_idle_ttl
    previous_legacy = Rails.configuration.x.session_token_ttl
    previous_absolute = Rails.configuration.x.session_token_absolute_ttl

    Rails.configuration.x.session_token_idle_ttl = idle_minutes.minutes
    Rails.configuration.x.session_token_ttl = idle_minutes.minutes
    Rails.configuration.x.session_token_absolute_ttl = absolute_minutes.minutes
    yield
  ensure
    Rails.configuration.x.session_token_idle_ttl = previous_idle
    Rails.configuration.x.session_token_ttl = previous_legacy
    Rails.configuration.x.session_token_absolute_ttl = previous_absolute
  end
end

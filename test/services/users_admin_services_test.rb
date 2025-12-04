require "test_helper"

class UsersAdminServicesTest < ActiveSupport::TestCase
  def setup
    @actor = User.create!(name: "Super", email_address: "super@example.com", password: "password", role: :superadmin, bid_credits: 0)
    @user = User.create!(name: "AdminCandidate", email_address: "candidate@example.com", password: "password", role: :user, bid_credits: 0)
  end

  test "grants admin role" do
    result = Admin::Users::GrantRole.new(actor: @actor, user: @user, role: :admin).call

    assert_nil result.error
    assert_equal "admin", result.user.role
  end

  test "rejects granting admin when already superadmin" do
    @user.update!(role: :superadmin)

    result = Admin::Users::GrantRole.new(actor: @actor, user: @user, role: :admin).call

    assert_equal "User is already a superadmin", result.error
  end

  test "revokes admin to user" do
    @user.update!(role: :admin)

    result = Admin::Users::GrantRole.new(actor: @actor, user: @user, role: :user).call

    assert_nil result.error
    assert_equal "user", result.user.role
  end

  test "bans a user and revokes sessions" do
    token = SessionToken.create!(user: @user, token_digest: SessionToken.digest("raw"), expires_at: 1.hour.from_now)

    result = Admin::Users::BanUser.new(actor: @actor, user: @user).call

    assert_nil result.error
    assert_equal "disabled", @user.reload.status
    assert token.reload.revoked_at.present?
  end

  test "ban errors if already disabled" do
    @user.update!(status: :disabled)

    result = Admin::Users::BanUser.new(actor: @actor, user: @user).call

    assert_equal "User already disabled", result.error
  end
end

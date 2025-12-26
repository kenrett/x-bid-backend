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

    result = Admin::Users::Disable.new(actor: @actor, user: @user).call

    assert_nil result.error
    assert_equal "disabled", @user.reload.status
    assert token.reload.revoked_at.present?
  end

  test "ban errors if already disabled" do
    @user.update!(status: :disabled)

    result = Admin::Users::Disable.new(actor: @actor, user: @user).call

    assert_nil result.error
    assert_equal :already_disabled, result.code
  end

  test "disable logs and revokes when active" do
    token = SessionToken.create!(user: @user, token_digest: SessionToken.digest("raw"), expires_at: 1.hour.from_now)
    logged = []

    result = AppLogger.stub(:log, ->(**payload) { logged << payload }) do
      Admin::Users::Disable.new(actor: @actor, user: @user, reason: "fraud").call
    end

    assert result.ok?
    assert_equal "disabled", @user.reload.status
    assert token.reload.revoked_at.present?
    assert_equal "admin.users.disable", logged.last[:event]
    assert_equal true, logged.last[:success]
    assert_equal "fraud", logged.last[:reason]
  end

  test "non-admin cannot disable a user" do
    result = Admin::Users::Disable.new(actor: @user, user: @user).call

    refute result.ok?
    assert_equal :forbidden, result.code
    assert_equal "active", @user.reload.status
  end

  test "adjust credits increases balance and logs" do
    logged = []

    result = AppLogger.stub(:log, ->(**payload) { logged << payload }) do
      Admin::Users::AdjustCredits.new(actor: @actor, user: @user, delta: 5, reason: "bonus").call
    end

    assert result.ok?
    assert_equal 5, @user.reload.bid_credits
    assert_equal 1, CreditTransaction.where(user_id: @user.id, kind: "adjustment", amount: 5).count
    assert_equal "admin.users.adjust_credits", logged.last[:event]
    assert_equal true, logged.last[:success]
    assert_equal 5, logged.last[:delta]
  end

  test "adjust credits rejects zero delta" do
    result = Admin::Users::AdjustCredits.new(actor: @actor, user: @user, delta: 0).call

    refute result.ok?
    assert_equal :invalid_delta, result.code
  end

  test "adjust credits cannot drive negative balance" do
    result = Admin::Users::AdjustCredits.new(actor: @actor, user: @user, delta: -1).call

    refute result.ok?
    assert_equal :insufficient_credits, result.code
    assert_equal 0, @user.reload.bid_credits
  end

  test "non-admin cannot adjust credits" do
    result = Admin::Users::AdjustCredits.new(actor: @user, user: @user, delta: 5).call

    refute result.ok?
    assert_equal :forbidden, result.code
  end
end

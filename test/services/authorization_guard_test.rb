require "test_helper"

class AuthorizationGuardTest < ActiveSupport::TestCase
  test "role checks: user/admin/superadmin" do
    user = create_actor(role: :user)
    admin = create_actor(role: :admin)
    superadmin = create_actor(role: :superadmin)

    assert Authorization::Guard.allow?(actor: user, role: :user)
    refute Authorization::Guard.allow?(actor: user, role: :admin)
    refute Authorization::Guard.allow?(actor: user, role: :superadmin)

    assert Authorization::Guard.allow?(actor: admin, role: :user)
    assert Authorization::Guard.allow?(actor: admin, role: :admin)
    refute Authorization::Guard.allow?(actor: admin, role: :superadmin)

    assert Authorization::Guard.allow?(actor: superadmin, role: :user)
    assert Authorization::Guard.allow?(actor: superadmin, role: :admin)
    assert Authorization::Guard.allow?(actor: superadmin, role: :superadmin)
  end

  test "default forbidden messages" do
    assert_equal "Admin privileges required", Authorization::Guard.default_forbidden_message(:admin)
    assert_equal "Superadmin privileges required", Authorization::Guard.default_forbidden_message(:superadmin)
  end

  test "ownership checks" do
    user = create_actor(role: :user)
    assert Authorization::Guard.owner?(actor: user, owner_id: user.id)
    refute Authorization::Guard.owner?(actor: user, owner_id: user.id + 1)
  end
end

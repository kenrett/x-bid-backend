module RoleMatrixHelpers
  # Yields a consistent role matrix for request specs.
  #
  # required_role:
  # - :admin => success for :admin and :superadmin
  # - :superadmin => success for :superadmin only
  #
  # Example:
  #   each_role_case(required_role: :admin, success_status: 200) do |role:, headers:, expected_status:, success:|
  #     get "/api/v1/admin/payments", headers: headers
  #     assert_response expected_status
  #   end
  #
  def each_role_case(required_role:, success_status:)
    yield(role: :unauthenticated, actor: nil, headers: {}, expected_status: 401, success: false)

    user = create_actor(role: :user)
    yield(role: :user, actor: user, headers: auth_headers_for(user), expected_status: 403, success: false)

    admin = create_actor(role: :admin)
    admin_success = required_role.to_sym == :admin
    yield(role: :admin, actor: admin, headers: auth_headers_for(admin), expected_status: (admin_success ? success_status : 403), success: admin_success)

    superadmin = create_actor(role: :superadmin)
    yield(role: :superadmin, actor: superadmin, headers: auth_headers_for(superadmin), expected_status: success_status, success: true)
  end
end

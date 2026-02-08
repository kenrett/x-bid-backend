require "test_helper"

class AuthSessionDocsContractTest < ActiveSupport::TestCase
  test "README auth section matches cookie-first runtime" do
    readme = read_doc("README.md")
    cookie_name = Auth::CookieSessionAuthenticator::COOKIE_NAME.to_s

    assert_includes readme, "cookie-first via signed `#{cookie_name}`"
    assert_includes readme, "`DELETE /logout`: Revoke the active session server-side and clear session cookies."
    refute_includes readme, "Log out (client-side session clearing)"
  end

  test "auth lifecycle doc avoids stale frontend storage assumptions" do
    auth_doc = read_doc("docs/auth.md")
    cookie_name = Auth::CookieSessionAuthenticator::COOKIE_NAME.to_s

    assert_includes auth_doc, "signed HttpOnly `#{cookie_name}` cookie"
    assert_includes auth_doc, "No assumption that frontend persists auth in `localStorage`."
    refute_includes auth_doc, "stores session data in localStorage"
    refute_includes auth_doc, "Reads session values from `localStorage`"
    refute_includes auth_doc, "`POST /api/v1/sessions`"
  end

  test "actioncable auth doc matches connection cookie source" do
    actioncable_doc = read_doc("docs/auth/actioncable.md")
    connection_source = read_doc("app/channels/application_cable/connection.rb")
    cookie_name = Auth::CookieSessionAuthenticator::COOKIE_NAME.to_s

    assert_includes connection_source, "cookies.signed[:#{cookie_name}]"
    assert_includes actioncable_doc, "cookies.signed[:#{cookie_name}]"
    refute_includes actioncable_doc, "?token="
  end

  test "subdomain auth checklist reflects cookie-first transport" do
    checklist = read_doc("docs/subdomain_auth_compatibility_checklist.md")

    assert_includes checklist, "HTTP API auth is cookie-first"
    refute_includes checklist, "cookies.encrypted[:jwt]"
  end

  private

  def read_doc(path)
    File.read(Rails.root.join(path))
  end
end

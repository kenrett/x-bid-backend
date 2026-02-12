require "test_helper"
require "rack/test"
require "uri"

class UploadsApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_actor(role: :user)
  end

  test "anonymous request can fetch upload content by valid signed_id" do
    host! "api.lvh.me"
    headers = auth_headers_for(@user)
    file = build_upload("hello.png", "image/png", "pngdata")

    post "/api/v1/uploads", params: { file: file }, headers: headers

    assert_response :success
    body = JSON.parse(response.body)
    public_url = body.fetch("public_url")
    signed_id = body.fetch("signed_id")

    assert_match(/\Ahttp/i, public_url)
    assert_includes public_url, "/api/v1/uploads/"

    public_uri = URI.parse(public_url)
    assert_equal "api.lvh.me", public_uri.host
    assert_equal "/api/v1/uploads/#{signed_id}", public_uri.path

    get public_url

    assert_response :redirect
    assert_match(/\Ahttp/i, response.headers["Location"])
    assert_equal "cross-origin", response.headers["Cross-Origin-Resource-Policy"]
    assert_match(/max-age=\d+/, response.headers["Cache-Control"].to_s)

    follow_redirect!
    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal "pngdata", response.body
  ensure
    file&.tempfile&.close!
  end

  test "anonymous request with invalid signed_id returns not found without invalid_token" do
    host! "api.lvh.me"
    get "/api/v1/uploads/invalid-signed-id"

    assert_response :not_found
    error = JSON.parse(response.body).fetch("error")
    refute_equal "invalid_token", error.fetch("code")
    assert_equal "not_found", error.fetch("code")
  end

  test "authenticated endpoints remain protected" do
    host! "api.lvh.me"
    get "/api/v1/me"

    assert_response :unauthorized
    error = JSON.parse(response.body).fetch("error")
    assert_equal "invalid_token", error.fetch("code")
  end

  private

  def build_upload(filename, content_type, body)
    tmpfile = Tempfile.new([ File.basename(filename, ".*"), File.extname(filename) ])
    tmpfile.binmode
    tmpfile.write(body)
    tmpfile.rewind
    Rack::Test::UploadedFile.new(tmpfile.path, content_type, original_filename: filename)
  end
end

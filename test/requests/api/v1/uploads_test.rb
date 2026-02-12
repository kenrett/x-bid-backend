require "test_helper"
require "rack/test"

class UploadsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_actor(role: :user)
  end

  test "POST /api/v1/uploads uploads a file and returns metadata" do
    host! "api.lvh.me"
    headers = auth_headers_for(@user)
    file = build_upload("hello.png", "image/png", "pngdata")

    post "/api/v1/uploads", params: { file: file }, headers: headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_kind_of String, body.fetch("url")
    assert_kind_of String, body.fetch("signed_id")
    assert_equal "hello.png", body.fetch("filename")
    assert_equal 7, body.fetch("byte_size")
  ensure
    file&.tempfile&.close!
  end

  test "GET /api/v1/uploads/:signed_id allows anonymous access for valid signed id" do
    host! "api.lvh.me"
    headers = auth_headers_for(@user)
    file = build_upload("hello.png", "image/png", "pngdata")

    post "/api/v1/uploads", params: { file: file }, headers: headers
    assert_response :success
    signed_id = JSON.parse(response.body).fetch("signed_id")

    get "/api/v1/uploads/#{signed_id}"

    assert_response :redirect
    assert_match(/\Ahttp/i, response.headers["Location"])
    assert_public_upload_redirect_cache_control!(response.headers["Cache-Control"])
    assert_equal "cross-origin", response.headers["Cross-Origin-Resource-Policy"]

    follow_redirect!
    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal "pngdata", response.body
  ensure
    file&.tempfile&.close!
  end

  test "GET /api/v1/uploads/:signed_id includes CORS headers for biddersweet frontend origin" do
    host! "api.lvh.me"
    headers = auth_headers_for(@user)
    file = build_upload("hello.png", "image/png", "pngdata")

    post "/api/v1/uploads", params: { file: file }, headers: headers
    assert_response :success
    signed_id = JSON.parse(response.body).fetch("signed_id")

    get "/api/v1/uploads/#{signed_id}", headers: { "Origin" => "https://www.biddersweet.app" }

    assert_response :redirect
    assert_equal "https://www.biddersweet.app", response.headers["Access-Control-Allow-Origin"]
    assert_equal "true", response.headers["Access-Control-Allow-Credentials"]
    assert_public_upload_redirect_cache_control!(response.headers["Cache-Control"])
    assert_equal "cross-origin", response.headers["Cross-Origin-Resource-Policy"]

    follow_redirect!
    assert_response :success
  ensure
    file&.tempfile&.close!
  end

  test "GET /api/v1/uploads/:signed_id returns not_found for invalid signed id without invalid_token" do
    host! "api.lvh.me"

    get "/api/v1/uploads/not-a-valid-signed-id"

    assert_response :not_found
    body = JSON.parse(response.body)
    assert_equal "not_found", body.dig("error", "code")
    refute_equal "invalid_token", body.dig("error", "code")
  end

  test "GET /api/v1/me remains protected without authentication" do
    host! "api.lvh.me"

    get "/api/v1/me"

    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "invalid_token", body.dig("error", "code")
  end

  test "POST /api/v1/uploads without a file returns 422" do
    host! "api.lvh.me"
    headers = auth_headers_for(@user)

    post "/api/v1/uploads", params: {}, headers: headers

    assert_equal 422, response.status
    body = JSON.parse(response.body)
    assert_equal "invalid_upload", body.dig("error", "code")
  end

  test "POST /api/v1/uploads with disallowed content type returns 422" do
    host! "api.lvh.me"
    headers = auth_headers_for(@user)
    file = build_upload("note.txt", "text/plain", "text")

    post "/api/v1/uploads", params: { file: file }, headers: headers

    assert_equal 422, response.status
    body = JSON.parse(response.body)
    assert_equal "invalid_upload", body.dig("error", "code")
  ensure
    file&.tempfile&.close!
  end

  test "POST /api/v1/uploads with oversized file returns 422" do
    host! "api.lvh.me"
    headers = auth_headers_for(@user)
    original_max = ENV["UPLOAD_MAX_MB"]
    ENV["UPLOAD_MAX_MB"] = "0"
    file = build_upload("big.png", "image/png", "x")

    post "/api/v1/uploads", params: { file: file }, headers: headers

    assert_equal 422, response.status
    body = JSON.parse(response.body)
    assert_equal "invalid_upload", body.dig("error", "code")
  ensure
    ENV["UPLOAD_MAX_MB"] = original_max
    file&.tempfile&.close!
  end

  private

  def build_upload(filename, content_type, body)
    tmpfile = Tempfile.new([ File.basename(filename, ".*"), File.extname(filename) ])
    tmpfile.binmode
    tmpfile.write(body)
    tmpfile.rewind
    Rack::Test::UploadedFile.new(tmpfile.path, content_type, original_filename: filename)
  end

  def assert_public_upload_redirect_cache_control!(cache_control)
    value = cache_control.to_s
    assert_includes value, "public"
    assert_match(/max-age=\d+/, value)
  end
end

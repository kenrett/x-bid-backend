require "test_helper"
require "rack/test"
require "uri"

class UploadsApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_actor(role: :user)
  end

  test "POST /api/v1/uploads returns public_url and GET redirects to service url" do
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

    get public_url, headers: headers

    assert_includes [ 302, 303 ], response.status
    assert_match(/\Ahttp/i, response.headers.fetch("Location"))
  ensure
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
end

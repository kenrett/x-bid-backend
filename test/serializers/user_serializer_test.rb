require "test_helper"

class UserSerializerTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(name: "User", email_address: "user4@example.com", password: "password", bid_credits: 5, role: :user)
  end

  test "serializes user with camel-cased keys" do
    json = UserSerializer.new(@user).as_json

    assert_equal @user.id, json[:id]
    assert_equal @user.name, json[:name]
    assert_equal @user.bid_credits, json[:bidCredits]
    assert_equal @user.email_address, json[:emailAddress]
  end
end

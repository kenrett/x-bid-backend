require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "should be valid with valid attributes" do
    user = User.new(email_address: "test@example.com", password: "password", role: :user)
    assert user.valid?
  end

  test "should be invalid without an email address" do
    user = User.new(password: "password", role: :user)
    refute user.valid?
    assert_not_nil user.errors[:email_address]
  end

  test "should normalize email address to downcase and strip whitespace" do
    user = User.create!(email_address: "  TEST@EXAMPLE.COM  ", password: "password", role: :user)
    assert_equal "test@example.com", user.email_address
  end

  test "should not allow negative bid_credits" do
    user = User.new(email_address: "test@example.com", password: "password", role: :user, bid_credits: -1)
    refute user.valid?
    assert_not_nil user.errors[:bid_credits]
  end

  test "should have many bids and won_auctions" do
    assert_respond_to User.new, :bids
    assert_respond_to User.new, :won_auctions
  end
end
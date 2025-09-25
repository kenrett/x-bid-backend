class Api::V1::BidsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_auction

  def create
    service = PlaceBid.new(
      user: current_user,
      auction: @auction,
      amount: bid_params[:amount].to_d
    )

    result = service.call

    if result.success?
      render json: {
        success: true,
        bid: {
          id: result.bid.id,
          amount: result.bid.amount,
          user_id: result.bid.user_id,
          created_at: result.bid.created_at
        },
        auction: {
          id: @auction.id,
          current_price: @auction.current_price,
          highest_bidder_id: @auction.winning_user_id,
          end_time: @auction.end_time
        }
      }, status: :created
    else
      render json: {
        success: false,
        error: result.error
      }, status: :unprocessable_entity
    end
  end

  private

  def set_auction
    @auction = Auction.find(params[:auction_id])
  end

  def bid_params
    params.require(:bid).permit(:amount)
  end
end

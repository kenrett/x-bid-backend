class Api::V1::BidPacksController < ApplicationController
  def index
    @bid_packs = BidPack.all

    render json: @bid_packs
  end
end

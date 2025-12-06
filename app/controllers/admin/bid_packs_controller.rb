module Admin
  class BidPacksController < ApplicationController
    before_action :authenticate_request!, :authorize_admin!
    before_action :set_bid_pack, only: [ :edit, :update ]

    # GET /admin/bid-packs
    def index
      bid_packs = BidPack.all
      render json: bid_packs
    end

    # GET /admin/bid-packs/new
    def new
      render json: BidPack.new
    end

    # GET /admin/bid-packs/:id/edit
    def edit
      render json: @bid_pack
    end

    # PATCH/PUT /admin/bid-packs/:id
    def update
      result = ::Admin::BidPacks::Upsert.new(actor: @current_user, bid_pack: @bid_pack, attrs: bid_pack_params, request: request).call
      if result.error
        render json: { errors: [ result.error ] }, status: :unprocessable_content
      else
        render json: result.record
      end
    end

    private

    def set_bid_pack
      @bid_pack = BidPack.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Bid pack not found" }, status: :not_found
    end

    def bid_pack_params
      params.require(:bid_pack).permit(:name, :bids, :price, :highlight, :description, :active)
    end
  end
end

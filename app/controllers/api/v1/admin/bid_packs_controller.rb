module Api
  module V1
    module Admin
      class BidPacksController < ApplicationController
        before_action :authenticate_request!, :authorize_admin!
        before_action :set_bid_pack, only: [:edit, :update]

        # GET /admin/bid_packs
        def index
          bid_packs = BidPack.all
          render json: bid_packs
        end

        # GET /admin/bid_packs/new
        def new
          render json: BidPack.new
        end

        # POST /admin/bid_packs
        def create
          bid_pack = BidPack.new(bid_pack_params)
          if bid_pack.save
            render json: bid_pack, status: :created
          else
            render json: { errors: bid_pack.errors.full_messages }, status: :unprocessable_entity
          end
        end

        # GET /admin/bid_packs/:id/edit
        def edit
          render json: @bid_pack
        end

        # PATCH/PUT /admin/bid_packs/:id
        def update
          if @bid_pack.update(bid_pack_params)
            render json: @bid_pack
          else
            render json: { errors: @bid_pack.errors.full_messages }, status: :unprocessable_entity
          end
        end

        private

        def set_bid_pack
          @bid_pack = BidPack.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Bid pack not found" }, status: :not_found
        end

        def bid_pack_params
          params.require(:bid_pack).permit(:name, :price, :bids, :highlight, :description, :active)
        end
      end
    end
  end
end

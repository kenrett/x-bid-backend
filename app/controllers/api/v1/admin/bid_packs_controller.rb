module Api
  module V1
    module Admin
      class BidPacksController < ApplicationController
        before_action :authenticate_request!, :authorize_admin!
        before_action :set_bid_pack, only: [:show, :edit, :update, :destroy]

        # GET /admin/bid_packs
        def index
          bid_packs = BidPack.all
          render json: bid_packs
        end

        # GET /admin/bid_packs/:id
        def show
          render json: @bid_pack
        end

        # GET /admin/bid_packs/new
        def new
          render json: BidPack.new
        end

        # POST /admin/bid_packs
        def create
          bid_pack = BidPack.new(bid_pack_params)
          if bid_pack.save
            AuditLogger.log(action: "bid_pack.create", actor: @current_user, target: bid_pack, payload: bid_pack_params.to_h)
            render json: bid_pack, status: :created
          else
            render json: { error: bid_pack.errors.full_messages.to_sentence }, status: :unprocessable_content
          end
        end

        # GET /admin/bid_packs/:id/edit
        def edit
          render json: @bid_pack
        end

        # PATCH/PUT /admin/bid_packs/:id
        def update
          if @bid_pack.update(bid_pack_params)
            AuditLogger.log(action: "bid_pack.update", actor: @current_user, target: @bid_pack, payload: bid_pack_params.to_h)
            render json: @bid_pack
          else
            render json: { error: @bid_pack.errors.full_messages.to_sentence }, status: :unprocessable_content
          end
        end

        # DELETE /admin/bid_packs/:id
        # Soft-deactivates a bid pack to prevent purchase while keeping history.
        def destroy
          if @bid_pack.update(active: false)
            AuditLogger.log(action: "bid_pack.delete", actor: @current_user, target: @bid_pack, payload: { active: false })
            render json: @bid_pack
          else
            render json: { error: @bid_pack.errors.full_messages.to_sentence }, status: :unprocessable_content
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

module Api
  module V1
    module Admin
      class BidPacksController < ApplicationController
        before_action :authenticate_request!, :authorize_admin!
        before_action :set_bid_pack, only: [ :show, :edit, :update, :destroy ]

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
          result = ::Admin::BidPacks::Upsert.new(actor: @current_user, attrs: bid_pack_params, request: request).call
          return render json: { error: result.error }, status: :unprocessable_content if result.error

          render json: result.record, status: :created
        end

        # GET /admin/bid_packs/:id/edit
        def edit
          render json: @bid_pack
        end

        # PATCH/PUT /admin/bid_packs/:id
        def update
          result = ::Admin::BidPacks::Upsert.new(actor: @current_user, bid_pack: @bid_pack, attrs: bid_pack_params, request: request).call
          return render json: { error: result.error }, status: :unprocessable_content if result.error

          render json: result.record
        end

        # DELETE /admin/bid_packs/:id
        # Retires a bid pack to prevent purchase while keeping history.
        def destroy
          result = ::Admin::BidPacks::Retire.new(actor: @current_user, bid_pack: @bid_pack, request: request).call
          return render json: { error: result.error }, status: :unprocessable_content if result.error

          render json: result.record
        end

        private

        def set_bid_pack
          @bid_pack = BidPack.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Bid pack not found" }, status: :not_found
        end

        def bid_pack_params
          permitted = params.require(:bid_pack).permit(:name, :price, :bids, :highlight, :description, :status, :active)

          # Map legacy `active` flag to the new status enum.
          if permitted.key?(:active)
            permitted[:status] = ActiveRecord::Type::Boolean.new.cast(permitted.delete(:active)) ? "active" : "retired"
          end

          permitted
        end
      end
    end
  end
end

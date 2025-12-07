module Admin
  class BidPacksController < ApplicationController
    before_action :authenticate_request!, :authorize_admin!
    before_action :set_bid_pack, only: [ :edit, :update, :destroy ]

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

    # POST /admin/bid-packs
    def create
      result = ::Admin::BidPacks::Upsert.new(actor: @current_user, attrs: bid_pack_params, request: request).call
      render_result(result, success_status: :created)
    end

    # PATCH/PUT /admin/bid-packs/:id
    def update
      result = ::Admin::BidPacks::Upsert.new(actor: @current_user, bid_pack: @bid_pack, attrs: bid_pack_params, request: request).call
      render_result(result)
    end

    # DELETE /admin/bid-packs/:id
    def destroy
      result = ::Admin::BidPacks::Retire.new(actor: @current_user, bid_pack: @bid_pack, request: request).call
      return head :no_content if result.ok?

      render json: { errors: [ result.error ] }, status: map_status(result.code)
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

    def render_result(result, success_status: :ok)
      return render json: { errors: [ result.error ] }, status: map_status(result.code) unless result.ok?

      render json: result.record, status: success_status
    end

    def map_status(code)
      case code
      when :forbidden then :forbidden
      when :invalid_state, :invalid_bid_pack then :unprocessable_content
      else :unprocessable_content
      end
    end
  end
end

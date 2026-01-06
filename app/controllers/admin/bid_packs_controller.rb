module Admin
  class BidPacksController < ApplicationController
    before_action :authenticate_request!
    before_action -> { authorize!(:admin) }
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

      render_error(code: result.code || :invalid_bid_pack, message: result.error || "Bid pack could not be retired", status: result.http_status)
    end

    private

    def set_bid_pack
      @bid_pack = BidPack.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render_error(code: :not_found, message: "Bid pack not found", status: :not_found)
    end

    def bid_pack_params
      params.require(:bid_pack).permit(:name, :bids, :price, :highlight, :description, :active)
    end

    def render_result(result, success_status: :ok)
      return render_error(code: result.code || :invalid_bid_pack, message: result.error || "Bid pack could not be saved", status: result.http_status) unless result.ok?

      render json: result.record, status: success_status
    end
  end
end

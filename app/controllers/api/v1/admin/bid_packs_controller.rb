module Api
  module V1
    module Admin
      class BidPacksController < ApplicationController
        before_action :authenticate_request!, :authorize_admin!
        before_action :set_bid_pack, only: [ :show, :edit, :update, :destroy ]

        # GET /admin/bid_packs
        # @summary List all bid packs (admin)
        # Lists all bid packs including retired ones for administrative management.
        # @response Bid packs (200) [Array<BidPack>]
        # @response Unauthorized (401) [Error]
        # @response Forbidden (403) [Error]
        def index
          bid_packs = BidPack.all
          render json: bid_packs
        end

        # GET /admin/bid_packs/:id
        # @summary Show a bid pack (admin)
        # @parameter id(path) [Integer] ID of the bid pack
        # @response Bid pack (200) [BidPack]
        # @response Unauthorized (401) [Error]
        # @response Forbidden (403) [Error]
        # @response Not found (404) [Error]
        def show
          render json: @bid_pack
        end

        # GET /admin/bid_packs/new
        # @summary Return a template bid pack for creation
        # @response Template (200) [BidPack]
        # @response Unauthorized (401) [Error]
        # @response Forbidden (403) [Error]
        def new
          render json: BidPack.new
        end

        # POST /admin/bid_packs
        # Create a bid pack with the provided attributes.
        # @request_body Bid pack payload (application/json) [!BidPackUpsert]
        # @response Bid pack created (201) [BidPack]
        # @response Unauthorized (401) [Error]
        # @response Forbidden (403) [Error]
        # @response Validation error (422) [Error]
        def create
          result = ::Admin::BidPacks::Upsert.new(actor: @current_user, attrs: bid_pack_params, request: request).call
          render_result(result, success_status: :created)
        end

        # GET /admin/bid_packs/:id/edit
        # @summary Fetch a bid pack for editing
        # @parameter id(path) [Integer] ID of the bid pack
        # @response Bid pack (200) [BidPack]
        # @response Unauthorized (401) [Error]
        # @response Forbidden (403) [Error]
        # @response Not found (404) [Error]
        def edit
          render json: @bid_pack
        end

        # PATCH/PUT /admin/bid_packs/:id
        # @summary Update a bid pack (admin)
        # Updates bid pack fields or status.
        # @parameter id(path) [Integer] ID of the bid pack
        # @request_body Bid pack payload (application/json) [!BidPackUpsert]
        # @response Bid pack updated (200) [BidPack]
        # @response Unauthorized (401) [Error]
        # @response Forbidden (403) [Error]
        # @response Not found (404) [Error]
        # @response Validation error (422) [Error]
        def update
          result = ::Admin::BidPacks::Upsert.new(actor: @current_user, bid_pack: @bid_pack, attrs: bid_pack_params, request: request).call
          render_result(result)
        end

        # DELETE /admin/bid_packs/:id
        # Retires a bid pack to prevent purchase while keeping history.
        # @summary Retire (deactivate) a bid pack (admin)
        # Retires an existing bid pack while preserving purchase history.
        # @parameter id(path) [Integer] ID of the bid pack
        # @response Bid pack retired (200) [BidPack]
        # @response Unauthorized (401) [Error]
        # @response Forbidden (403) [Error]
        # @response Not found (404) [Error]
        # @response Validation error (422) [Error]
        def destroy
          result = ::Admin::BidPacks::Retire.new(actor: @current_user, bid_pack: @bid_pack, request: request).call
          render_result(result)
        end

        private

        def set_bid_pack
          @bid_pack = BidPack.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error(code: :not_found, message: "Bid pack not found", status: :not_found)
        end

        def bid_pack_params
          permitted = params.require(:bid_pack).permit(:name, :price, :bids, :highlight, :description, :status, :active)

          # Map legacy `active` flag to the new status enum.
          if permitted.key?(:active)
            permitted[:status] = ActiveRecord::Type::Boolean.new.cast(permitted.delete(:active)) ? "active" : "retired"
          end

          permitted
        end

        def render_result(result, success_status: :ok)
          if result.ok?
            return render json: result.record, status: success_status
          end

          render_error(code: result.code || :invalid_bid_pack, message: result.error, status: map_status(result.code))
        end

        def map_status(code)
          case code
          when :forbidden then :forbidden
          when :invalid_state, :invalid_bid_pack, :invalid_status then :unprocessable_content
          else :unprocessable_content
          end
        end
      end
    end
  end
end

module Api
  module V1
    class AuctionsController < ApplicationController
      before_action :authenticate_request!, :authorize_admin!, only: [:create, :update, :destroy]
      resource_description do
        short 'Auction management'
        description 'Endpoints for viewing and managing auctions.'
      end

      api :GET, '/auctions', 'List all auctions'
      description 'Returns a list of all auctions. This endpoint is public.'
      def index
        auctions = Auction.all
        render json: auctions
      end

      api :GET, '/auctions/:id', 'Show a single auction'
      description 'Returns the details for a specific auction, including its bid history.'
      param :id, :number, desc: 'ID of the auction', required: true
      error code: 404, desc: 'Not Found'
      def show
        auction = Auction.includes(:bids).find(params[:id])
        render json: auction, include: :bids
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Auction not found' }, status: :not_found
      end

      api :POST, "/auctions", "Create a new auction (admin only)"
      param :auction, Hash, required: true do
        param :title, String, required: true
        param :description, String
        param :image_url, String
        param :status, String
        param :start_date, DateTime
        param :end_time, DateTime
        param :current_price, BigDecimal
      end
      def create
        auction = Auction.new(auction_params)
        if auction.save
          render json: auction, status: :created
        else
          render json: { errors: auction.errors.full_messages }, status: :unprocessable_entity
        end
      end

      api :PUT, "/auctions/:id", "Update an auction (admin only)"
      def update
        auction = Auction.find(params[:id])
        if auction.update(auction_params)
          render json: auction
        else
          render json: { errors: auction.errors.full_messages }, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Auction not found" }, status: :not_found
      end

      api :DELETE, "/auctions/:id", "Delete an auction (admin only)"
      def destroy
        auction = Auction.find(params[:id])
        auction.destroy
        head :no_content
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Auction not found" }, status: :not_found
      end

      private

      def auction_params
        params.require(:auction).permit(
          :title,
          :description,
          :image_url,
          :status,
          :start_date,
          :end_time,
          :current_price
        )
      end
    end
  end
end

module Api
  module V1
    class AuctionsController < ApplicationController
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

      # Note: The create, update, and destroy actions would also be documented here.
      # They would likely require admin authorization.
      # include Authorization
      # before_action :authenticate_request!, :authorize_admin!, only: [:create, :update, :destroy]
    end
  end
end
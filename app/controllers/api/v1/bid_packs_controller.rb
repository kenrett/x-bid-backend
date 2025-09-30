module Api
  module V1
    class BidPacksController < ApplicationController
      resource_description do
        short 'Bid Pack management'
      end

      api :GET, '/bid_packs', 'List all available bid packs'
      def index
        bid_packs = BidPack.all
        render json: bid_packs
      end
    end
  end
end
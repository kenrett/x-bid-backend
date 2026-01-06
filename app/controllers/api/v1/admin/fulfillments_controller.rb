module Api
  module V1
    module Admin
      class FulfillmentsController < ApplicationController
        before_action :authenticate_request!
        before_action -> { authorize!(:admin) }
        before_action :set_fulfillment

        # POST /api/v1/admin/fulfillments/:id/process
        # @summary Move fulfillment from claimed -> processing
        def process_fulfillment
          result = ::Admin::Fulfillments::Process.new(
            actor: @current_user,
            fulfillment: @fulfillment,
            shipping_cost_cents: process_params[:shipping_cost_cents],
            notes: process_params[:notes],
            request: request
          ).call

          return render_error(code: result.code || :unprocessable_content, message: result.error, status: result.http_status) unless result.ok?

          render json: Api::V1::Admin::FulfillmentSerializer.new(result.record).as_json
        end

        # POST /api/v1/admin/fulfillments/:id/ship
        # @summary Move fulfillment from processing -> shipped
        def ship
          result = ::Admin::Fulfillments::Ship.new(
            actor: @current_user,
            fulfillment: @fulfillment,
            shipping_carrier: ship_params[:shipping_carrier],
            tracking_number: ship_params[:tracking_number],
            request: request
          ).call

          return render_error(code: result.code || :unprocessable_content, message: result.error, status: result.http_status) unless result.ok?

          render json: Api::V1::Admin::FulfillmentSerializer.new(result.record).as_json
        end

        # POST /api/v1/admin/fulfillments/:id/complete
        # @summary Move fulfillment from shipped -> complete
        def complete
          result = ::Admin::Fulfillments::Complete.new(
            actor: @current_user,
            fulfillment: @fulfillment,
            request: request
          ).call

          return render_error(code: result.code || :unprocessable_content, message: result.error, status: result.http_status) unless result.ok?

          render json: Api::V1::Admin::FulfillmentSerializer.new(result.record).as_json
        end

        private

        def set_fulfillment
          @fulfillment = AuctionFulfillment.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error(code: :not_found, message: "Fulfillment not found", status: :not_found) and return
        end

        def process_params
          params.permit(:shipping_cost_cents, :notes)
        end

        def ship_params
          params.permit(:shipping_carrier, :tracking_number)
        end
      end
    end
  end
end

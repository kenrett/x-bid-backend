module Api
  module V1
    module Admin
      class PaymentsController < ApplicationController
        before_action :authenticate_request!, :authorize_admin!

        # GET /api/v1/admin/payments
        # @summary List payments with optional email search
        def index
          payments = Purchase.includes(:user, :bid_pack).order(created_at: :desc)
          payments = payments.joins(:user).where("LOWER(users.email_address) LIKE ?", "%#{params[:search].downcase}%") if params[:search].present?

          render json: payments.map { |payment| serialize_payment(payment) }
        end

        private

        def serialize_payment(payment)
          {
            id: payment.id,
            user_email: payment.user.email_address,
            amount: payment.bid_pack.price,
            status: payment.status,
            created_at: payment.created_at
          }
        end
      end
    end
  end
end

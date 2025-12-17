module Api
  module V1
    module Admin
      class PaymentsController < ApplicationController
        before_action :authenticate_request!, :authorize_admin!

        # GET /api/v1/admin/payments
        # @summary List payments with optional email search
        # Lists purchases with optional fuzzy email search for admins.
        # @parameter search(query) [String] Filter payments by user email substring
        # @response Payments (200) [Array<Hash{ id: Integer, user_email: String, amount: Float, refunded_cents: Integer, status: String, created_at: String }>]
        # @response Unauthorized (401) [Error]
        # @response Forbidden (403) [Error]
        def index
          payments = Purchase.includes(:user, :bid_pack).order(created_at: :desc)
          payments = payments.joins(:user).where("LOWER(users.email_address) LIKE ?", "%#{params[:search].downcase}%") if params[:search].present?

          render json: payments.map { |payment| serialize_payment(payment) }
        end

        # POST /api/v1/admin/payments/:id/refund
        # @summary Issue a refund for a payment
        # Issues a refund for a payment and records the refund ID from the gateway.
        # @parameter id(path) [Integer] ID of the payment
        # @request_body Refund payload (application/json) [PaymentRefundRequest]
        # @response Refund issued (200) [Hash{ id: Integer, user_email: String, amount: Float, refunded_cents: Integer, status: String, created_at: String, refund_id: String }]
        # @response Unauthorized (401) [Error]
        # @response Forbidden (403) [Error]
        # @response Not found (404) [Error]
        # @response Validation error (422) [Error]
        def refund
          payment = Purchase.find(params[:id])
          result = ::Admin::Payments::IssueRefund.new(
            actor: @current_user,
            payment: payment,
            amount_cents: params[:amount_cents],
            reason: params[:reason],
            request: request
          ).call

          if result.ok?
            render json: serialize_payment(payment.reload).merge(refund_id: result.data[:refund_id]), status: :ok
          else
            render_error(code: result.code || :refund_failed, message: result.error, status: result.http_status)
          end
        rescue ActiveRecord::RecordNotFound
          render_error(code: :not_found, message: "Payment not found", status: :not_found)
        end

        private

        def serialize_payment(payment)
          amount = payment.amount_cents.to_i.positive? ? payment.amount_cents / 100.0 : payment.bid_pack.price
          {
            id: payment.id,
            user_email: payment.user.email_address,
            amount: amount,
            refunded_cents: payment.refunded_cents,
            status: payment.status,
            created_at: payment.created_at
          }
        end
      end
    end
  end
end

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

        # POST /api/v1/admin/payments/:id/refund
        # @summary Issue a refund for a payment
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
            render_error(code: result.code || :refund_failed, message: result.error, status: map_status(result.code))
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

        def map_status(code)
          case code
          when :forbidden then :forbidden
          when :invalid_amount, :invalid_state, :amount_exceeds_charge, :gateway_error, :already_refunded then :unprocessable_entity
          else :unprocessable_content
          end
        end
      end
    end
  end
end

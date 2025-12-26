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

        # GET /api/v1/admin/payments/:id
        # @summary Show a payment reconciliation view
        # Returns the purchase, related credit transactions, and a balance audit for admins.
        def show
          payment = Purchase.includes(:user, :bid_pack).find(params[:id])
          credit_transactions = CreditTransaction.where(purchase_id: payment.id).order(created_at: :asc)
          audit = Credits::AuditBalance.call(user: payment.user)

          render json: {
            purchase: serialize_payment_detail(payment),
            credit_transactions: credit_transactions.map { |tx| serialize_credit_transaction(tx) },
            balance_audit: audit
          }
        rescue ActiveRecord::RecordNotFound
          render_error(code: :not_found, message: "Payment not found", status: :not_found)
        end

        # POST /api/v1/admin/payments/:id/repair_credits
        # @summary Repair missing purchase credits
        # Ensures the ledger grant exists for a completed purchase without double-crediting.
        def repair_credits
          payment = Purchase.find(params[:id])
          result = ::Admin::Payments::RepairCredits.new(actor: @current_user, purchase: payment, request: request).call

          unless result.ok?
            return render_error(code: result.code || :repair_failed, message: result.error, status: result.http_status)
          end

          payment = payment.reload
          credit_transactions = CreditTransaction.where(purchase_id: payment.id).order(created_at: :asc)
          audit = Credits::AuditBalance.call(user: payment.user)

          render json: {
            idempotent: !!result.idempotent,
            purchase: serialize_payment_detail(payment),
            credit_transactions: credit_transactions.map { |tx| serialize_credit_transaction(tx) },
            balance_audit: audit
          }, status: :ok
        rescue ActiveRecord::RecordNotFound
          render_error(code: :not_found, message: "Payment not found", status: :not_found)
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
            created_at: payment.created_at,
            stripe_checkout_session_id: payment.stripe_checkout_session_id,
            stripe_payment_intent_id: payment.stripe_payment_intent_id,
            stripe_event_id: payment.stripe_event_id
          }
        end

        def serialize_payment_detail(payment)
          {
            id: payment.id,
            user_email: payment.user.email_address,
            bid_pack: {
              id: payment.bid_pack.id,
              name: payment.bid_pack.name
            },
            amount_cents: payment.amount_cents,
            currency: payment.currency,
            status: payment.status,
            stripe_checkout_session_id: payment.stripe_checkout_session_id,
            stripe_payment_intent_id: payment.stripe_payment_intent_id,
            stripe_event_id: payment.stripe_event_id,
            created_at: payment.created_at
          }
        end

        def serialize_credit_transaction(tx)
          {
            id: tx.id,
            kind: tx.kind,
            amount: tx.amount,
            reason: tx.reason,
            idempotency_key: tx.idempotency_key,
            created_at: tx.created_at
          }
        end
      end
    end
  end
end

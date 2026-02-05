class Api::V1::WalletController < ApplicationController
  before_action :authenticate_request!

  # GET /api/v1/wallet
  # @summary Show current credits balance
  # Returns the user's current credits balance, derived from the append-only ledger,
  # plus an audit comparison against the cached `bid_credits` column.
  # @response Wallet balance (200) [WalletBalance]
  # @response Unauthorized (401) [Error]
  def show
    derived = Credits::Balance.derived_for_user(@current_user)
    audit = Credits::AuditBalance.call(user: @current_user)

    render json: {
      credits_balance: Credits::Balance.for_user(@current_user),
      balance_source: balance_source_for(@current_user),
      balance_audit: audit,
      as_of: Time.current.utc.iso8601
    }
  end

  # GET /api/v1/wallet/transactions
  # @summary List wallet ledger transactions (newest first)
  # Returns a paginated view of the user's append-only ledger history.
  # @parameter page(query) [Integer] Page number (1-indexed)
  # @parameter per_page(query) [Integer] Page size (default 25, max 100)
  # @response Wallet transactions (200) [WalletTransactions]
  # @response Unauthorized (401) [Error]
  def transactions
    result = Credits::Queries::LedgerForUser.call(
      user: @current_user,
      params: ledger_params
    )

    render json: {
      transactions: result.records.map { |entry| Api::V1::CreditTransactionSerializer.new(entry).as_json },
      page: result.meta.fetch(:page),
      per_page: result.meta.fetch(:per_page),
      has_more: result.meta.fetch(:has_more)
    }
  end

  private

  def ledger_params
    params.permit(:page, :per_page)
  end

  def balance_source_for(user)
    CreditTransaction.exists?(user_id: user.id) ? "ledger_derived" : "cached"
  end
end

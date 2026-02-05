class CreditsReconcileBalancesJob < ApplicationJob
  queue_as :default

  def perform(fix: false, limit: nil)
    Credits::ReconcileBalances.call!(fix: fix, limit: limit)
  end
end

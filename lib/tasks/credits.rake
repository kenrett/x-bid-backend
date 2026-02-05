namespace :credits do
  desc "Reconcile materialized credit balances against the ledger"
  task reconcile_balances: :environment do
    fix = ENV.fetch("FIX", "false") == "true"
    limit = ENV["LIMIT"]&.to_i
    stats = Credits::ReconcileBalances.call!(fix: fix, limit: limit)
    puts "checked=#{stats[:checked]} drifted=#{stats[:drifted]} fixed=#{stats[:fixed]}"
  end
end

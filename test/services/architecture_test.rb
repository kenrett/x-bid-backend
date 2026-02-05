require "test_helper"

class ArchitectureTest < ActiveSupport::TestCase
  SERVICE_ROOT = Rails.root.join("app/services").freeze

  test "public services do not depend on Admin namespace" do
    offending_files = Dir.glob(SERVICE_ROOT.join("**/*.rb")).reject { |path| path.include?("/admin/") }.select do |path|
      File.read(path).match?(/\bAdmin::/)
    end

    assert offending_files.empty?, <<~MSG
      Non-admin services must not reference Admin::* namespaces.
      Offending files:
      #{offending_files.join("\n")}
    MSG
  end

  test "services/controllers do not directly mutate bid_credits" do
    roots = [
      Rails.root.join("app/services"),
      Rails.root.join("app/controllers")
    ]

    allowlist = [
      Rails.root.join("app/services/credits/rebuild_balance.rb").to_s,
      Rails.root.join("app/services/credits/materialized_balance.rb").to_s
    ]

    forbidden = [
      /increment!\(\s*:bid_credits\b/,
      /decrement!\(\s*:bid_credits\b/,
      /\bupdate!(\s*|\s*\()\s*bid_credits\s*:/,
      /\bupdate_columns\(\s*bid_credits\s*:/,
      /\bupdate_column\(\s*:bid_credits\b/,
      /\bupdate_attribute\(\s*:bid_credits\b/
    ]

    offending_files = roots.flat_map { |root| Dir.glob(root.join("**/*.rb")) }.uniq.reject { |path| allowlist.include?(path) }.select do |path|
      contents = File.read(path)
      forbidden.any? { |pattern| contents.match?(pattern) }
    end

    assert offending_files.empty?, <<~MSG
      Direct bid_credits mutations are forbidden; use ledger-backed services instead.
      Offending files:
      #{offending_files.join("\n")}
    MSG
  end
end

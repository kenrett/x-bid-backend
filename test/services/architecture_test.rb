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
end

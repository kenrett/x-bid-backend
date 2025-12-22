require "json"
require "fileutils"

namespace :openapi do
  desc "Generate OpenAPI spec into docs/api/openapi.json"
  task generate: :environment do
    output_path = Rails.root.join("docs", "api", "openapi.json")
    FileUtils.mkdir_p(output_path.dirname)

    spec_json = JSON.pretty_generate(JSON.parse(OasRails.build.to_json))
    File.write(output_path, "#{spec_json}\n")

    puts "Wrote #{output_path}"
  end
end

require "json"
require "fileutils"
require "digest"

namespace :openapi do
  desc "Generate OpenAPI spec into docs/api/openapi.json"
  task generate: :environment do
    output_path = Rails.root.join("docs", "api", "openapi.json")
    FileUtils.mkdir_p(output_path.dirname)

    spec_hash = JSON.parse(OasRails.build.to_json)
    canonicalize_components!(spec_hash, "responses", "resp_")
    canonicalize_components!(spec_hash, "requestBodies", "req_")
    spec_hash = deep_sort(spec_hash)

    spec_json = JSON.pretty_generate(spec_hash)
    File.write(output_path, "#{spec_json}\n")

    puts "Wrote #{output_path}"
  end

  def deep_sort(value)
    case value
    when Hash
      value.keys.sort.to_h { |key| [ key, deep_sort(value[key]) ] }
    when Array
      value.map { |v| deep_sort(v) }
    else
      value
    end
  end

  def canonicalize_components!(spec_hash, component_key, prefix)
    components = spec_hash.dig("components", component_key) || {}

    canonicalized = components.to_h do |old_key, content|
      canonical_content = deep_sort(content)
      digest = Digest::SHA256.hexdigest(JSON.generate(canonical_content))
      [ old_key, [ digest, canonical_content ] ]
    end

    digest_to_new_key = {}
    new_components = {}

    canonicalized.values.uniq { |digest, _| digest }
      .sort_by { |digest, _| digest }
      .each_with_index do |(digest, content), idx|
        new_key = "#{prefix}#{format('%03d', idx + 1)}"
        digest_to_new_key[digest] = new_key
        new_components[new_key] = content
      end

    mapping = canonicalized.to_h do |old_key, (digest, _)|
      [ old_key, digest_to_new_key.fetch(digest) ]
    end

    spec_hash["components"] ||= {}
    spec_hash["components"][component_key] = new_components
    update_refs!(spec_hash, "#/components/#{component_key}/", mapping)
  end

  def update_refs!(obj, ref_prefix, mapping)
    case obj
    when Hash
      obj.each do |key, value|
        if key == "$ref" && value.is_a?(String) && value.start_with?(ref_prefix)
          original_key = value.delete_prefix(ref_prefix)
          obj[key] = "#{ref_prefix}#{mapping.fetch(original_key, original_key)}"
        else
          update_refs!(value, ref_prefix, mapping)
        end
      end
    when Array
      obj.each { |value| update_refs!(value, ref_prefix, mapping) }
    end
  end
end

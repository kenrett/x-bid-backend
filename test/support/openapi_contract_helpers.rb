require "json"
require "json-schema"
require "set"

module OpenapiContractHelpers
  OpenapiContractError = Class.new(StandardError)

  def assert_openapi_response_schema!(method:, path:, status:)
    schema = openapi_schema_for_response(method:, path:, status:)
    return if schema.nil?

    body_text = response.body.to_s
    data = body_text.present? ? JSON.parse(body_text) : nil

    errors = JSON::Validator.fully_validate(schema, data, validate_schema: true)
    assert(
      errors.empty?,
      "OpenAPI schema validation failed for #{method.to_s.upcase} #{path} (#{status}).\n#{errors.join("\n")}"
    )
  end

  private

  def openapi_schema_for_response(method:, path:, status:)
    operation = openapi_operation_for(method:, path:)
    responses = operation.fetch("responses")

    status_key = status.to_s
    response_def =
      responses[status_key] ||
        responses["#{status_key[0]}XX"] ||
        responses["default"]

    raise OpenapiContractError, "No OpenAPI response schema for #{method.to_s.upcase} #{path} status #{status_key}" unless response_def

    content = response_def["content"]
    return nil unless content.is_a?(Hash) && content.any?

    media = content["application/json"] || content.values.first
    return nil unless media.is_a?(Hash)

    schema = media["schema"]
    return nil unless schema

    resolved = resolve_openapi_schema(schema)
    normalized = normalize_openapi_schema_for_json_schema(resolved)
    normalized["$schema"] ||= "http://json-schema.org/draft-04/schema#"
    normalized
  end

  def openapi_operation_for(method:, path:)
    method_key = method.to_s.downcase
    paths = openapi_document.fetch("paths")

    template, item = paths.find do |template_path, path_item|
      next false unless path_item.is_a?(Hash)
      next false unless path_item.key?(method_key)

      path_matches_template?(path, template_path)
    end

    raise OpenapiContractError, "No OpenAPI operation for #{method.to_s.upcase} #{path}" unless template

    item.fetch(method_key)
  end

  def path_matches_template?(path, template_path)
    return true if path == template_path

    pattern = Regexp.escape(template_path).gsub("\\{", "{").gsub("\\}", "}")
    pattern = pattern.gsub(/\{[^}]+\}/, "[^/]+")
    !!(/\A#{pattern}\z/.match?(path))
  end

  def openapi_document
    @openapi_document ||= begin
      openapi_path = Rails.root.join("docs", "api", "openapi.json")
      raise OpenapiContractError, "Missing OpenAPI spec at #{openapi_path} (run `rake openapi:generate`)" unless File.exist?(openapi_path)

      JSON.parse(File.read(openapi_path))
    end
  end

  def resolve_openapi_schema(schema, seen_refs: Set.new)
    schema = schema.deep_dup
    return schema unless schema.is_a?(Hash)

    if schema.key?("$ref")
      ref = schema.fetch("$ref")
      raise OpenapiContractError, "Unsupported $ref: #{ref}" unless ref.start_with?("#/")
      raise OpenapiContractError, "Circular $ref: #{ref}" if seen_refs.include?(ref)

      seen_refs = seen_refs.dup.add(ref)
      resolved = resolve_json_pointer(openapi_document, ref.delete_prefix("#/"))
      resolved = resolve_openapi_schema(resolved, seen_refs:)

      siblings = schema.except("$ref")
      return resolved.merge(siblings)
    end

    schema.each do |key, value|
      case value
      when Hash
        schema[key] = resolve_openapi_schema(value, seen_refs:)
      when Array
        schema[key] = value.map { |v| v.is_a?(Hash) ? resolve_openapi_schema(v, seen_refs:) : v }
      end
    end

    schema
  end

  def resolve_json_pointer(document, pointer)
    pointer.split("/").reduce(document) do |current, token|
      key = token.gsub("~1", "/").gsub("~0", "~")
      current.fetch(key)
    end
  rescue KeyError => e
    raise OpenapiContractError, "Unable to resolve $ref pointer '#{pointer}': #{e.message}"
  end

  def normalize_openapi_schema_for_json_schema(schema)
    return schema unless schema.is_a?(Hash)

    schema = schema.deep_dup
    schema.delete("example")
    schema.delete("examples")
    schema.delete("deprecated")
    schema.delete("externalDocs")
    schema.delete("xml")
    schema.delete("discriminator")

    if schema.delete("nullable")
      schema = allow_null_schema(schema)
    end

    schema.each do |key, value|
      case value
      when Hash
        schema[key] = normalize_openapi_schema_for_json_schema(value)
      when Array
        schema[key] = value.map { |v| v.is_a?(Hash) ? normalize_openapi_schema_for_json_schema(v) : v }
      end
    end

    schema
  end

  def allow_null_schema(schema)
    if schema.key?("type")
      type = schema["type"]
      schema["type"] = type.is_a?(Array) ? (type + [ "null" ]).uniq : [ type, "null" ]
      return schema
    end

    { "anyOf" => [ schema, { "type" => "null" } ] }
  end
end

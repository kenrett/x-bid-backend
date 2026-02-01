namespace :storage do
  desc "Attach and read back an Active Storage blob using the configured service"
  task smoke: :environment do
    required_env_vars = %w[
      S3_BUCKET
      AWS_REGION
      AWS_ACCESS_KEY_ID
      AWS_SECRET_ACCESS_KEY
    ]

    missing = required_env_vars.select { |key| ENV[key].to_s.strip.empty? }
    if missing.any?
      puts "Skipping Active Storage smoke test; missing env vars: #{missing.join(", ")}"
      next
    end

    service_name = :amazon
    ActiveStorage::Service.configure(service_name, Rails.configuration.active_storage.service_configurations)

    data = "storage-smoke-#{SecureRandom.hex(8)}"
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(data),
      filename: "storage-smoke.txt",
      content_type: "text/plain",
      service_name: service_name
    )

    downloaded = blob.download
    if downloaded != data
      blob.purge
      raise "Smoke test failed: downloaded data does not match"
    end

    blob.purge
    puts "Active Storage smoke test passed (service #{blob.service.name})"
  end
end

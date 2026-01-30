namespace :active_storage do
  desc "Backfill local disk Active Storage blobs to S3"
  task backfill_to_s3: :environment do
    configurations = Rails.configuration.active_storage.service_configurations
    source = ActiveStorage::Service.configure(:local, configurations)
    destination = ActiveStorage::Service.configure(:amazon, configurations)

    unless destination.respond_to?(:upload)
      raise "amazon service is not configured"
    end

    migrated = 0
    skipped = 0
    missing = 0
    failed = 0

    ActiveStorage::Blob.find_each do |blob|
      key = blob.key

      if destination.exist?(key)
        skipped += 1
        next
      end

      begin
        source.open(key, checksum: blob.checksum) do |io|
          destination.upload(
            key,
            io,
            checksum: blob.checksum,
            content_type: blob.content_type,
            disposition: blob.disposition,
            filename: blob.filename
          )
        end
        migrated += 1
      rescue ActiveStorage::FileNotFoundError
        missing += 1
        puts "Missing local file for blob #{blob.id} (#{key})"
      rescue StandardError => e
        failed += 1
        puts "Failed blob #{blob.id} (#{key}): #{e.class} #{e.message}"
      end
    end

    puts "Backfill complete: migrated=#{migrated} skipped=#{skipped} missing=#{missing} failed=#{failed}"
    raise "Backfill failed for #{failed} blob(s)" if failed.positive?
  end
end

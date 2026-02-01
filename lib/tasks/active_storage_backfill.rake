namespace :active_storage do
  desc "Backfill local disk Active Storage blobs to S3"
  task backfill_to_s3: :environment do
    configurations = Rails.configuration.active_storage.service_configurations
    source_service_name = :local
    destination_service_name = :amazon
    source = ActiveStorage::Service.configure(source_service_name, configurations)
    destination = ActiveStorage::Service.configure(destination_service_name, configurations)

    unless destination.respond_to?(:upload)
      raise "amazon service is not configured"
    end

    batch_size = Integer(ENV.fetch("BATCH_SIZE", "1000"))
    start_id = ENV["START_ID"].to_s.strip
    end_id = ENV["END_ID"].to_s.strip

    start_id = start_id.empty? ? nil : Integer(start_id)
    end_id = end_id.empty? ? nil : Integer(end_id)

    migrated = 0
    skipped = 0
    missing = 0
    failed = 0
    last_id = nil

    scope = ActiveStorage::Blob.where(service_name: [ nil, source_service_name.to_s ]).order(:id)
    scope = scope.where("id >= ?", start_id) if start_id
    scope = scope.where("id <= ?", end_id) if end_id

    puts "Starting Active Storage backfill to #{destination_service_name} (batch_size=#{batch_size}, start_id=#{start_id || "none"}, end_id=#{end_id || "none"})"

    scope.in_batches(of: batch_size) do |relation|
      relation.each do |blob|
        last_id = blob.id
        key = blob.key

        begin
          if destination.exist?(key)
            blob.update!(service_name: destination_service_name.to_s)
            skipped += 1
            next
          end

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

          # Verify integrity after upload using the stored checksum.
          destination.open(key, checksum: blob.checksum) { |_io| }
          blob.update!(service_name: destination_service_name.to_s)
          migrated += 1
        rescue ActiveStorage::FileNotFoundError
          missing += 1
          puts "Missing local file for blob #{blob.id} (#{key})"
        rescue StandardError => e
          failed += 1
          puts "Failed blob #{blob.id} (#{key}): #{e.class} #{e.message}"
        end
      end

      processed = migrated + skipped + missing + failed
      puts "Progress: processed=#{processed} last_id=#{last_id} migrated=#{migrated} skipped=#{skipped} missing=#{missing} failed=#{failed}"
    end

    puts "Backfill complete: migrated=#{migrated} skipped=#{skipped} missing=#{missing} failed=#{failed} last_id=#{last_id}"
    raise "Backfill failed for #{failed} blob(s)" if failed.positive?
  end
end

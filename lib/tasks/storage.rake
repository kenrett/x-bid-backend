namespace :storage do
  desc "Attach and read back an Active Storage blob using the configured service"
  task smoke: :environment do
    data = "storage-smoke-#{SecureRandom.hex(8)}"
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(data),
      filename: "storage-smoke.txt",
      content_type: "text/plain"
    )

    downloaded = blob.download
    if downloaded != data
      blob.purge
      raise "Smoke test failed: downloaded data does not match"
    end

    blob.purge
    puts "Active Storage smoke test passed (service #{ActiveStorage::Blob.service.name})"
  end
end

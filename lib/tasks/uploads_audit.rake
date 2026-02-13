require "set"
require "json"

namespace :uploads do
  desc "Audit ActiveStorage blobs vs S3 objects"
  task audit: :environment do
    bucket = ENV.fetch("S3_BUCKET")
    region = ENV.fetch("AWS_REGION")
    prefix = ENV.fetch("UPLOADS_PREFIX", "")

    s3 = Aws::S3::Client.new(region: region)
    s3_keys = []
    token = nil

    loop do
      resp = s3.list_objects_v2(
        bucket: bucket,
        prefix: prefix,
        continuation_token: token
      )
      s3_keys.concat(resp.contents.map(&:key))
      break unless resp.is_truncated
      token = resp.next_continuation_token
    end

    s3_set = s3_keys.to_set
    db_set = ActiveStorage::Blob.pluck(:key).to_set

    missing_in_db = (s3_set - db_set).to_a
    missing_in_s3 = (db_set - s3_set).to_a

    report = {
      s3_count: s3_set.size,
      db_count: db_set.size,
      missing_in_db_count: missing_in_db.size,
      missing_in_s3_count: missing_in_s3.size,
      missing_in_db: missing_in_db.take(200),
      missing_in_s3: missing_in_s3.take(200)
    }

    File.write(Rails.root.join("tmp/uploads_audit.json"), JSON.pretty_generate(report))
    puts JSON.pretty_generate(report)
  end
end

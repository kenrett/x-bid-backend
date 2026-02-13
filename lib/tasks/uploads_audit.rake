require "json"

begin
  require "aws-sdk-s3"
rescue LoadError
  # Uploads::AuditReport surfaces a clear error if the SDK is unavailable.
end

namespace :uploads do
  desc "Audit ActiveStorage blobs vs S3 objects"
  task audit: :environment do
    bucket = Uploads::AuditReport.bucket_from_env
    abort "Missing required env var: set AWS_BUCKET (preferred) or S3_BUCKET." if bucket.blank?

    region = Uploads::AuditReport.region_from_env
    abort "Missing required env var: AWS_REGION." if region.blank?

    prefix = ENV.fetch("UPLOADS_PREFIX", "")

    report_path = Uploads::AuditReport::REPORT_PATH
    report = Uploads::AuditReport.new(bucket: bucket, region: region, prefix: prefix).write_report(path: report_path)

    puts JSON.pretty_generate(report)
    puts "Wrote report to #{report_path}"
  rescue Uploads::AuditReport::MissingDependencyError => e
    abort e.message
  end
end

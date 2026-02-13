require "json"
require "set"

module Uploads
  class AuditReport
    REPORT_PATH = Rails.root.join("tmp/uploads_audit.json")

    class MissingDependencyError < StandardError; end

    def self.bucket_from_env(env = ENV)
      aws_bucket = env["AWS_BUCKET"]
      s3_bucket = env["S3_BUCKET"]
      return aws_bucket if aws_bucket.present?
      return s3_bucket if s3_bucket.present?

      nil
    end

    def self.region_from_env(env = ENV)
      region = env["AWS_REGION"]
      return region if region.present?

      nil
    end

    def initialize(bucket:, region:, prefix: "", s3_client: nil, blob_keys: nil)
      @bucket = bucket
      @region = region
      @prefix = prefix
      @blob_keys = blob_keys
      @s3_client = s3_client || build_s3_client
    end

    def call
      s3_set = fetch_s3_keys.to_set
      db_set = db_blob_keys.to_set

      missing_in_db = (s3_set - db_set).to_a.sort
      missing_in_s3 = (db_set - s3_set).to_a.sort

      {
        s3_count: s3_set.size,
        db_count: db_set.size,
        missing_in_db_count: missing_in_db.size,
        missing_in_s3_count: missing_in_s3.size,
        missing_in_db: missing_in_db.take(200),
        missing_in_s3: missing_in_s3.take(200)
      }
    end

    def write_report(path: REPORT_PATH)
      report = call
      File.write(path, JSON.pretty_generate(report))
      report
    end

    private

    attr_reader :bucket, :region, :prefix, :blob_keys, :s3_client

    def build_s3_client
      unless defined?(Aws::S3::Client)
        raise MissingDependencyError, "Missing dependency: aws-sdk-s3. Run `bundle install` and retry."
      end

      Aws::S3::Client.new(region: region)
    end

    def fetch_s3_keys
      keys = []
      continuation_token = nil

      loop do
        response = s3_client.list_objects_v2(
          bucket: bucket,
          prefix: prefix,
          continuation_token: continuation_token
        )

        keys.concat(Array(response.contents).map(&:key).compact)
        break unless response.is_truncated

        continuation_token = response.next_continuation_token
      end

      keys
    end

    def db_blob_keys
      return blob_keys if blob_keys

      ActiveStorage::Blob.pluck(:key)
    end
  end
end

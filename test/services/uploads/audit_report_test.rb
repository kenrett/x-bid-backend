require "test_helper"

module Uploads
  class AuditReportTest < ActiveSupport::TestCase
    S3Object = Struct.new(:key)
    S3Response = Struct.new(:contents, :is_truncated, :next_continuation_token)

    test "bucket_from_env prefers AWS_BUCKET and falls back to S3_BUCKET" do
      assert_equal "aws-bucket", AuditReport.bucket_from_env({ "AWS_BUCKET" => "aws-bucket", "S3_BUCKET" => "legacy-bucket" })
      assert_equal "legacy-bucket", AuditReport.bucket_from_env({ "S3_BUCKET" => "legacy-bucket" })
      assert_nil AuditReport.bucket_from_env({})
    end

    test "region_from_env reads AWS_REGION" do
      assert_equal "us-west-2", AuditReport.region_from_env({ "AWS_REGION" => "us-west-2" })
      assert_nil AuditReport.region_from_env({})
    end

    test "builds a report from paginated S3 keys and blob keys" do
      client = FakeS3Client.new(
        [
          S3Response.new([ S3Object.new("uploads/a"), S3Object.new("uploads/b") ], true, "token-1"),
          S3Response.new([ S3Object.new("uploads/c") ], false, nil)
        ]
      )

      report = AuditReport.new(
        bucket: "example-bucket",
        region: "us-west-2",
        prefix: "uploads/",
        s3_client: client,
        blob_keys: [ "uploads/b", "uploads/c", "uploads/d" ]
      ).call

      assert_equal 3, report[:s3_count]
      assert_equal 3, report[:db_count]
      assert_equal 1, report[:missing_in_db_count]
      assert_equal 1, report[:missing_in_s3_count]
      assert_equal [ "uploads/a" ], report[:missing_in_db]
      assert_equal [ "uploads/d" ], report[:missing_in_s3]
      assert_equal [
        { bucket: "example-bucket", prefix: "uploads/", continuation_token: nil },
        { bucket: "example-bucket", prefix: "uploads/", continuation_token: "token-1" }
      ], client.requests
    end

    test "writes the report JSON to disk" do
      client = FakeS3Client.new([ S3Response.new([ S3Object.new("uploads/key-1") ], false, nil) ])
      report_path = Rails.root.join("tmp/uploads_audit_test.json")
      File.delete(report_path) if File.exist?(report_path)

      report = AuditReport.new(
        bucket: "example-bucket",
        region: "us-west-2",
        prefix: "uploads/",
        s3_client: client,
        blob_keys: []
      ).write_report(path: report_path)

      parsed = JSON.parse(File.read(report_path))
      assert_equal report[:s3_count], parsed["s3_count"]
      assert_equal report[:missing_in_db_count], parsed["missing_in_db_count"]
    ensure
      File.delete(report_path) if report_path && File.exist?(report_path)
    end

    class FakeS3Client
      attr_reader :requests

      def initialize(responses)
        @responses = responses.dup
        @requests = []
      end

      def list_objects_v2(bucket:, prefix:, continuation_token:)
        @requests << { bucket: bucket, prefix: prefix, continuation_token: continuation_token }
        response = @responses.shift
        raise "Unexpected list_objects_v2 call" unless response

        response
      end
    end
  end
end

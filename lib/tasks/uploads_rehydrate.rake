require "cgi"

namespace :uploads do
  desc "Regenerate Auction.image_url from attached ActiveStorage blobs"
  task rehydrate_auction_image_urls: :environment do
    dry_run = ENV["DRY_RUN"] == "1"
    only_missing = ENV["ONLY_MISSING"] == "1"

    unless defined?(Auction)
      abort "Auction model not found"
    end

    unless Auction.column_names.include?("image_url")
      abort "Auction.image_url column not found"
    end

    updated = 0
    skipped = 0
    missing_attachment = 0

    Auction.find_each do |auction|
      unless auction.respond_to?(:image) && auction.image.attached?
        missing_attachment += 1
        next
      end

      signed_id = auction.image.blob.signed_id
      next if signed_id.blank?

      new_url = "/api/v1/uploads/#{CGI.escape(signed_id)}"

      if only_missing && auction.image_url.present?
        skipped += 1
        next
      end

      if auction.image_url == new_url
        skipped += 1
        next
      end

      if dry_run
        puts "[DRY_RUN] Auction ##{auction.id}: #{auction.image_url.inspect} -> #{new_url.inspect}"
      else
        auction.update_columns(image_url: new_url, updated_at: Time.current)
      end

      updated += 1
    rescue => e
      warn "Auction ##{auction.id} failed: #{e.class} #{e.message}"
    end

    puts "Done. updated=#{updated} skipped=#{skipped} missing_attachment=#{missing_attachment} dry_run=#{dry_run}"
  end
end

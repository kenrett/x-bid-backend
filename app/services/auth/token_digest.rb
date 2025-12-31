require "digest"

module Auth
  module TokenDigest
    def self.digest(raw_token)
      Digest::SHA256.hexdigest(raw_token.to_s)
    end
  end
end

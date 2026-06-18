# frozen_string_literal: true

module MyInvois
  # Caches access tokens per hotel TIN to avoid re-authenticating on every call.
  # Tokens are valid for 60 minutes; we cache for 55 to give a safety buffer.
  class TokenStore
    CACHE_EXPIRY = 55.minutes

    def self.fetch(tin:, environment:, &block)
      key = "myinvois_token:#{environment}:#{tin}"
      cached = Rails.cache.read(key)
      return cached if cached.present?

      result = block.call
      Rails.cache.write(key, result[:token], expires_in: CACHE_EXPIRY)
      result[:token]
    end

    def self.invalidate(tin:, environment:)
      Rails.cache.delete("myinvois_token:#{environment}:#{tin}")
    end
  end
end

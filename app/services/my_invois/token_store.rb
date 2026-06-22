# frozen_string_literal: true

module MyInvois
  # Caches access tokens per hotel TIN to avoid re-authenticating on every call.
  # Tokens are valid for 60 minutes; we cache for 55 to give a safety buffer.
  class TokenStore
    CACHE_EXPIRY = 55.minutes

    def self.fetch(tin:, environment:, mode:, represented_taxpayer_tin: nil, &block)
      key = cache_key(tin:, environment:, mode:, represented_taxpayer_tin:)
      cached = Rails.cache.read(key)
      return cached if cached.present?

      result = block.call
      Rails.cache.write(key, result[:token], expires_in: CACHE_EXPIRY)
      result[:token]
    rescue StandardError
      Rails.cache.delete(key)
      raise
    end

    def self.invalidate(tin:, environment:, mode:, represented_taxpayer_tin: nil)
      Rails.cache.delete(cache_key(tin:, environment:, mode:, represented_taxpayer_tin:))
    end

    def self.cache_key(tin:, environment:, mode:, represented_taxpayer_tin: nil)
      [ "myinvois_token", environment, mode, tin, represented_taxpayer_tin.presence || "self" ].join(":")
    end
  end
end

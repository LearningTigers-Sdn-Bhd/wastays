# frozen_string_literal: true

module HotelKnowledges
  # Turns a guest's question into a vector, once.
  #
  # Guests ask the same twenty questions forever -- "what time is check in",
  # "do you have parking" -- and every one of them used to be a fresh call to
  # an embedding API before a single row was read. The cache is not scoped to
  # a hotel because an embedding depends on the model, not on who is asking;
  # the same sentence at a different hotel is the same vector.
  #
  # Failures are not cached: `Rails.cache.fetch` lets the error out of the
  # block, so a provider outage does not get remembered as an answer.
  class EmbedQuery
    CACHE_VERSION = "v1"
    TTL = 30.days

    def initialize(hotel:, query:)
      @hotel = hotel
      @query = query.to_s.strip
    end

    def call
      return if query.blank?

      Rails.cache.fetch(cache_key, expires_in: TTL) do
        EmbeddingService.new(hotel: hotel).call([ query ]).first
      end
    end

    private

    attr_reader :hotel, :query

    def cache_key
      [
        "hotel_knowledges/embed_query",
        CACHE_VERSION,
        EmbeddingService::MODEL,
        EmbeddingService::DIMENSIONS,
        Digest::SHA256.hexdigest(query.downcase.squish)
      ].join("/")
    end
  end
end

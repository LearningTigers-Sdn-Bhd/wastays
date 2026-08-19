# frozen_string_literal: true

module HotelKnowledges
  class SearchService
    DEFAULT_LIMIT = 5

    # `query_vector:` lets a caller that is about to search the same question
    # more than once embed it a single time. Without one, the service embeds
    # for itself, so every existing caller keeps working unchanged.
    def initialize(hotel:, query:, categories:, limit: DEFAULT_LIMIT, query_vector: nil)
      @hotel = hotel
      @query = query.to_s.strip
      @categories = Array(categories).map(&:to_s).reject(&:blank?)
      @limit = limit.to_i.positive? ? limit.to_i : DEFAULT_LIMIT
      @query_vector = query_vector
    end

    def call
      return [] if query.blank? || categories.empty?

      vector = query_vector || EmbedQuery.new(hotel: hotel, query: query).call
      return [] if vector.blank?

      matching_chunks(vector).map { |chunk| normalize_chunk(chunk) }
    rescue EmbeddingError
      []
    end

    private

    attr_reader :hotel, :query, :categories, :limit, :query_vector

    def matching_chunks(query_vector)
      HotelKnowledgeChunk
        .joins(:document)
        .includes(:document)
        .where(hotel_knowledge_documents: {
          hotel_id: hotel.id,
          category: categories,
          embedding_status: "indexed"
        })
        .where.not(embedding: nil)
        .nearest_neighbors(:embedding, query_vector, distance: "cosine")
        .limit(limit)
    end

    def normalize_chunk(chunk)
      document = chunk.document

      {
        "content" => chunk.content,
        "document_title" => document.title,
        "category" => document.category,
        "language" => document.language,
        "version" => document.version,
        "chunk_index" => chunk.chunk_index,
        "distance" => neighbor_distance(chunk)
      }
    end

    def neighbor_distance(chunk)
      if chunk.respond_to?(:neighbor_distance)
        chunk.neighbor_distance
      elsif chunk.respond_to?(:distance)
        chunk.distance
      else
        chunk[:neighbor_distance]
      end
    rescue StandardError
      nil
    end
  end
end

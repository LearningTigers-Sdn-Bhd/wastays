# frozen_string_literal: true

module HotelKnowledges
  class SearchService
    DEFAULT_LIMIT = 5

    # Reciprocal rank fusion. The constant damps the influence of the top few
    # positions so that one engine being confidently wrong cannot outvote the
    # other agreeing quietly; 60 is the value the original RRF paper settled on
    # and there is no reason here to invent a different one.
    RRF_K = 60

    # `query_vector:` lets a caller that is about to search the same question
    # more than once embed it a single time. Without one, the service embeds
    # for itself, so every existing caller keeps working unchanged.
    def initialize(hotel:, query:, categories:, limit: DEFAULT_LIMIT, query_vector: nil,
                   keyword_search: KeywordSearchService)
      @hotel = hotel
      @query = query.to_s.strip
      @categories = Array(categories).map(&:to_s).reject(&:blank?)
      @limit = limit.to_i.positive? ? limit.to_i : DEFAULT_LIMIT
      @query_vector = query_vector
      @keyword_search = keyword_search
    end

    def call
      return [] if query.blank? || categories.empty?

      fuse(vector_matches, keyword_matches).first(limit)
    end

    private

    attr_reader :hotel, :query, :categories, :limit, :query_vector, :keyword_search

    def vector_matches
      vector = query_vector || EmbedQuery.new(hotel: hotel, query: query).call
      return [] if vector.blank?

      matching_chunks(vector).map { |chunk| normalize_chunk(chunk) }
    rescue EmbeddingError
      # Meaning is unavailable, but words still are. Losing the embedding
      # provider used to lose the whole answer.
      []
    end

    def keyword_matches
      keyword_search.new(hotel: hotel, query: query, categories: categories, limit: limit).call
    end

    # Two ranked lists, fused by position rather than by score, because a cosine
    # distance and a ts_rank are not measured in the same units and averaging
    # them would be arithmetic on nonsense.
    #
    # `distance` is carried over from the vector list untouched, and stays nil
    # on a keyword-only row: HybridAnswerBuilder reads it against
    # STRONG_MATCH_DISTANCE, and inventing a number here would be putting words
    # in the retriever's mouth. What a row does gain is `retrieval`, so a
    # caller can tell "both engines agree" from "one engine guessed".
    def fuse(vector_rows, keyword_rows)
      scores = Hash.new(0.0)
      found_by = Hash.new { |hash, key| hash[key] = [] }
      rows = {}

      { "vector" => vector_rows, "keyword" => keyword_rows }.each do |engine, list|
        list.each_with_index do |row, index|
          key = identity(row)
          scores[key] += 1.0 / (RRF_K + index + 1)
          found_by[key] << engine
          rows[key] = rows.key?(key) ? merge_rows(rows[key], row) : row
        end
      end

      scores
        .sort_by { |key, score| [ -score, rows[key]["chunk_index"].to_i ] }
        .map { |key, _score| rows[key].merge("retrieval" => found_by[key]) }
    end

    def identity(row) = [ row["document_title"], row["chunk_index"], row["content"] ]

    # The vector row wins on `distance` because it is the only one that has a
    # real one.
    def merge_rows(existing, incoming)
      existing["distance"].nil? ? incoming.merge(existing.compact) : existing
    end

    def matching_chunks(vector)
      HotelKnowledgeChunk
        .joins(:document)
        .includes(:document)
        .where(hotel_knowledge_documents: {
          hotel_id: hotel.id,
          category: categories,
          embedding_status: "indexed"
        })
        .where.not(embedding: nil)
        .nearest_neighbors(:embedding, vector, distance: "cosine")
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

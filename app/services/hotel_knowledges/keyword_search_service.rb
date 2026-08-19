# frozen_string_literal: true

module HotelKnowledges
  # Finds chunks by the words they actually contain.
  #
  # Vector search is weakest exactly where hotel guests are most specific:
  # names. "Deluxe Seaview", a wifi SSID, a dish on the menu -- cosine
  # similarity happily returns a chunk that is *about* the same subject while
  # missing the one that names the thing. Postgres does full text search in the
  # same database, so the fix costs a column and an index rather than a service
  # to operate.
  class KeywordSearchService
    DEFAULT_LIMIT = 5

    # 'simple' rather than 'english': hotel corpora here are not all English,
    # and English stemming degrades every chunk that is not. The cost is that
    # 'simple' keeps stopwords, so they are removed below instead.
    CONFIGURATION = "simple"
    MIN_TERM_LENGTH = 3
    MAX_TERMS = 12

    STOP_WORDS = %w[
      the and are was were you your our its for with that this from have has had
      can could would should does did any all not but what when where which who
      how why there here about into out per via yes
    ].freeze

    def initialize(hotel:, query:, categories:, limit: DEFAULT_LIMIT)
      @hotel = hotel
      @query = query.to_s.strip
      @categories = Array(categories).map(&:to_s).reject(&:blank?)
      @limit = limit.to_i.positive? ? limit.to_i : DEFAULT_LIMIT
    end

    def call
      return [] if categories.empty? || terms.empty?

      matching_chunks.map { |chunk| normalize_chunk(chunk) }
    end

    private

    attr_reader :hotel, :query, :categories, :limit

    def matching_chunks
      HotelKnowledgeChunk
        .joins(:document)
        .includes(:document)
        .where(hotel_knowledge_documents: {
          hotel_id: hotel.id,
          category: categories,
          embedding_status: "indexed"
        })
        .where("content_tsv @@ #{tsquery_sql}", tsquery)
        .order(Arel.sql(HotelKnowledgeChunk.sanitize_sql_array([ "ts_rank(content_tsv, #{tsquery_sql}) DESC", tsquery ])))
        .limit(limit)
    end

    # Terms are OR'd rather than AND'd, and ts_rank does the discriminating.
    # Requiring every word would mean a guest who writes a sentence rather than
    # a search box gets nothing -- which is most guests.
    def tsquery = terms.join(" | ")

    def tsquery_sql = "to_tsquery('#{CONFIGURATION}', ?)"

    # Punctuation is stripped rather than escaped: what reaches to_tsquery is
    # only ever alphanumeric words, so nothing a guest types can be read as
    # query syntax.
    def terms
      @terms ||= query
        .downcase
        .gsub(/[^[:alnum:]\s]/, " ")
        .split
        .reject { |term| term.length < MIN_TERM_LENGTH || STOP_WORDS.include?(term) }
        .uniq
        .first(MAX_TERMS)
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
        "distance" => nil
      }
    end
  end
end

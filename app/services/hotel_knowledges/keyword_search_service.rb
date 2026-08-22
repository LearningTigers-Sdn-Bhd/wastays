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
    #
    # Both fragments are written out in full rather than interpolated from a
    # constant, so nothing about the SQL is assembled at runtime -- the only
    # value that varies is the bound one.
    MATCHES_SQL = "content_tsv @@ to_tsquery('simple', ?)"
    RANK_SQL = "ts_rank(content_tsv, to_tsquery('simple', ?)) DESC"

    MIN_TERM_LENGTH = 3
    MAX_TERMS = 12

    STOP_WORDS = %w[
      the and are was were you your our its for with that this from have has had
      can could would should does did any all not but what when where which who
      how why there here about into out per via yes
    ].freeze

    def initialize(hotel:, query:, categories:, limit: DEFAULT_LIMIT, extra_terms: [])
      @hotel = hotel
      @query = query.to_s.strip
      @categories = Array(categories).map(&:to_s).reject(&:blank?)
      @limit = limit.to_i.positive? ? limit.to_i : DEFAULT_LIMIT
      @extra_terms = Array(extra_terms)
    end

    def call
      return [] if categories.empty? || terms.empty?

      matching_chunks.map { |chunk| normalize_chunk(chunk) }
    end

    private

    attr_reader :hotel, :query, :categories, :limit, :extra_terms

    def matching_chunks
      HotelKnowledgeChunk
        .joins(:document)
        .includes(:document)
        .where(hotel_knowledge_documents: {
          hotel_id: hotel.id,
          category: categories,
          embedding_status: "indexed"
        })
        .where(MATCHES_SQL, tsquery)
        .order(Arel.sql(HotelKnowledgeChunk.sanitize_sql_array([ RANK_SQL, tsquery ])))
        .limit(limit)
    end

    # Terms are OR'd rather than AND'd, and ts_rank does the discriminating.
    # Requiring every word would mean a guest who writes a sentence rather than
    # a search box gets nothing -- which is most guests.
    def tsquery = terms.join(" | ")

    # Punctuation is stripped rather than escaped: what reaches to_tsquery is
    # only ever alphanumeric words, so nothing a guest types can be read as
    # query syntax.
    # Supplied terms come first so that the cap cannot spend itself on the
    # guest's own words before reaching them. That matters most where they
    # matter most: a question with no spaces in it tokenises into one long
    # non-word, which survives the length test and would otherwise take a slot
    # while matching nothing.
    def terms
      @terms ||= tokenize([ *extra_terms, query ].join(" "))
    end

    def tokenize(text)
      text
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

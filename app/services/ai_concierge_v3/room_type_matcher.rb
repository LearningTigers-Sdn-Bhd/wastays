module AiConciergeV3
  class RoomTypeMatcher
    ROOM_TYPE_IGNORED_TOKENS = %w[
      a about an any details do does faq for have i info is me need of room suite tell the this villa want what with
    ].freeze

    def initialize(room_types:, query:, hinted_room_type_name: nil)
      @room_types = Array(room_types)
      @query = query.to_s
      @hinted_room_type_name = hinted_room_type_name.to_s.presence
    end

    def call
      return success(exact_hint_match) if exact_hint_match
      return success(exact_query_match) if exact_query_match

      return ambiguous(fuzzy_matches) if fuzzy_matches.many?
      return success(fuzzy_matches.first) if fuzzy_matches.one?

      not_found
    end

    private

    attr_reader :room_types, :query, :hinted_room_type_name

    def success(room_type)
      {
        "success" => true,
        "room_type" => room_type
      }
    end

    def ambiguous(matches)
      {
        "success" => false,
        "error" => "ambiguous_room_type",
        "room_type_names" => matches.map(&:name)
      }
    end

    def not_found
      {
        "success" => false,
        "error" => "room_type_not_found"
      }
    end

    def exact_hint_match
      return unless hinted_room_type_name.present?

      room_types.find { |room_type| normalize(room_type.name) == normalize(hinted_room_type_name) }
    end

    def exact_query_match
      room_types.find { |room_type| normalized_query.include?(normalize(room_type.name)) }
    end

    def fuzzy_matches
      @fuzzy_matches ||= room_types.select do |room_type|
        room_type_tokens_match?(room_type.name)
      end
    end

    def room_type_tokens_match?(room_type_name)
      room_tokens = normalize(room_type_name).split
      return false if room_tokens.empty? || query_tokens.empty?

      consecutive_token_match?(room_tokens) || all_query_tokens_match?(room_tokens)
    end

    def consecutive_token_match?(room_tokens)
      max_start = room_tokens.length - query_tokens.length
      return false if max_start.negative?

      (0..max_start).any? do |start_index|
        query_tokens.each_with_index.all? do |token, offset|
          room_tokens[start_index + offset].start_with?(token)
        end
      end
    end

    def all_query_tokens_match?(room_tokens)
      query_tokens.all? do |token|
        room_tokens.any? { |room_token| room_token.start_with?(token) }
      end
    end

    def normalized_query
      @normalized_query ||= normalize(query)
    end

    def query_tokens
      @query_tokens ||= normalized_query.split.reject do |token|
        ROOM_TYPE_IGNORED_TOKENS.include?(token) || token.match?(/^\d+$/)
      end
    end

    def normalize(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
    end
  end
end

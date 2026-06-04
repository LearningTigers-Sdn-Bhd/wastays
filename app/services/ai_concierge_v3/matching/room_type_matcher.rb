module AiConciergeV3
  module Matching
    class RoomTypeMatcher
    ROOM_TYPE_IGNORED_TOKENS = %w[
      a about an any detail details do does faq for have i info is me need of room suite tell the this villa want what with
    ].freeze
    ROOM_TYPE_SUFFIX_TOKENS = %w[room rooms suite suites villa villas apartment apartments cabin cabins].freeze
    TOKEN_ALIASES = {
      "exec" => "executive",
      "prem" => "premium",
      "dlx" => "deluxe",
      "std" => "standard",
      "apt" => "apartment"
    }.freeze

    def initialize(room_types:, query:, hinted_room_type_name: nil)
      @room_types = Array(room_types)
      @query = query.to_s
      @hinted_room_type_name = hinted_room_type_name.to_s.presence
    end

    def call
      return success(exact_hint_match) if exact_hint_match
      return success(exact_query_match) if exact_query_match

      matches = fuzzy_matches
      return ambiguous(matches) if matches.many?
      return success(matches.first) if matches.one?

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
      @fuzzy_matches ||= begin
        scored = room_types.filter_map do |room_type|
          score = room_type_match_score(room_type.name)
          [ room_type, score ] if score.positive?
        end
        if scored.empty?
          []
        else
          best_score = scored.map(&:last).max
          scored.select { |_room_type, score| score == best_score }.map(&:first)
        end
      end
    end

    def room_type_match_score(room_type_name)
      room_tokens = significant_tokens(room_type_name)
      return 0 if room_tokens.empty? || query_tokens.empty?

      return 4 if consecutive_token_match?(room_tokens)
      return 3 if all_query_tokens_match?(room_tokens)
      return 2 if all_query_tokens_fuzzy_match?(room_tokens)

      0
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
        room_tokens.any? { |room_token| room_token.start_with?(token) || token.start_with?(room_token) }
      end
    end

    def all_query_tokens_fuzzy_match?(room_tokens)
      return false if query_tokens.size > room_tokens.size

      query_tokens.all? do |token|
        room_tokens.any? { |room_token| small_typo_match?(token, room_token) }
      end
    end

    def normalized_query
      @normalized_query ||= normalize(query)
    end

    def query_tokens
      @query_tokens ||= significant_tokens(query).reject do |token|
        ROOM_TYPE_IGNORED_TOKENS.include?(token) || token.match?(/^\d+$/)
      end
    end

    def significant_tokens(value)
      normalize(value).split.filter_map do |token|
        normalized_token = singularize(TOKEN_ALIASES.fetch(token, token))
        next if room_type_suffix_token?(normalized_token)

        normalized_token
      end
    end

    def room_type_suffix_token?(token)
      ROOM_TYPE_SUFFIX_TOKENS.include?(token) ||
        token.start_with?("suit") ||
        token.start_with?("vill") ||
        token.start_with?("room")
    end

    def singularize(token)
      return token.delete_suffix("ies") + "y" if token.length > 4 && token.end_with?("ies")
      return token.delete_suffix("s") if token.length > 3 && token.end_with?("s")

      token
    end

    def small_typo_match?(left, right)
      return true if left == right
      return true if left.length >= 4 && right.start_with?(left)
      return true if right.length >= 4 && left.start_with?(right)
      return false if (left.length - right.length).abs > 1
      return false if [ left.length, right.length ].min < 4

      levenshtein_distance(left, right) <= 1
    end

    def levenshtein_distance(left, right)
      previous = (0..right.length).to_a
      left.each_char.with_index(1) do |left_char, i|
        current = [ i ]
        right.each_char.with_index(1) do |right_char, j|
          current[j] = if left_char == right_char
            previous[j - 1]
          else
            [ previous[j], current[j - 1], previous[j - 1] ].min + 1
          end
        end
        previous = current
      end
      previous.last
    end

    def normalize(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
    end
    end
  end
end

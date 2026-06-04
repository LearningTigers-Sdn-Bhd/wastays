module AiConciergeV3
  module Tools
    module Booking
      class SelectBookingOptionTool
        ROOM_TYPE_IGNORED_TOKENS = %w[
          a an and book booking can choice choose chose for go i in is me my number ok on option pick picked please room suite take the this to villa want with
          jan january feb february mar march apr april may jun june jul july aug august sep september oct october nov november dec december
          first second third one two three four five six seven eight nine ten
        ].freeze
        ROOM_TYPE_SUFFIX_TOKENS = %w[room rooms suite suites villa villas apartment apartments cabin cabins].freeze
        TOKEN_ALIASES = {
          "exec" => "executive",
          "prem" => "premium",
          "dlx" => "deluxe",
          "std" => "standard",
          "apt" => "apartment"
        }.freeze

        def initialize(option_number:, suggested_options:, suggestion_set_version: nil, selection_id: nil, check_in: nil, message: nil, pending_selection: nil)
          @option_number = option_number.to_i
          @suggested_options = Array(suggested_options)
          @suggestion_set_version = suggestion_set_version
          @selection_id = selection_id.to_s.presence
          @check_in = check_in.to_s.presence
          @message = message.to_s
          @pending_selection = pending_selection.is_a?(Hash) ? pending_selection : {}
        end

        def call
          option = selected_option
          return option if option.is_a?(Hash) && option["success"] == false
          return ({ "success" => false, "error" => "invalid_selection" }) unless option

          {
            "success" => true,
            "selected_option" => option,
            "suggestion_set_version" => suggestion_set_version
          }
        end

        private

        attr_reader :option_number, :suggested_options, :suggestion_set_version, :selection_id, :check_in, :message, :pending_selection

        def selected_option
          return find_by_selection_id if selection_id.present?
          return find_by_room_type_and_date if check_in.present? && resolved_room_type_name.present?
          return find_by_date if check_in.present?
          return find_by_option_number if resolved_option_number.positive?
          return find_by_room_type_name if mentioned_room_type_name(groups).present?

          nil
        end

        def find_by_selection_id
          flattened_options.find { |option| option["selection_id"] == selection_id }
        end

        def find_by_date
          matches = flattened_options.select { |option| option["check_in"] == check_in }
          return matches.first if matches.one?

          narrowed_matches = narrow_by_room_type(matches)
          return narrowed_matches.first if narrowed_matches.one?
          return room_type_requires_option_number_result(resolved_room_type_name) if narrowed_matches.many? && resolved_room_type_name.present?
          return ambiguous_date_result(matches) if matches.many?

          nil
        end

        def find_by_room_type_and_date
          group = groups.find { |candidate| normalized(candidate["room_type_name"]) == normalized(resolved_room_type_name) }
          return unless group

          matches = group.fetch("options", []).select { |option| option["check_in"] == check_in }

          return matches.first if matches.one?
          return room_type_requires_option_number_result(resolved_room_type_name) if matches.many?

          nil
        end

        def find_by_option_number
          matching_groups = candidate_groups.select do |group|
            group.fetch("options", []).any? { |option| option["position"].to_i == resolved_option_number }
          end

          return matching_groups.first.fetch("options").find { |option| option["position"].to_i == resolved_option_number } if matching_groups.one?

          room_type_name = mentioned_room_type_name(matching_groups)
          return select_from_group(room_type_name, resolved_option_number) if room_type_name.present?
          return ambiguous_option_result(matching_groups) if matching_groups.many?

          nil
        end

        def select_from_group(room_type_name, position)
          group = groups.find { |candidate| normalized(candidate["room_type_name"]) == normalized(room_type_name) }
          return unless group

          group.fetch("options", []).find { |option| option["position"].to_i == position }
        end

        def find_by_room_type_name
          room_type_name = resolved_room_type_name
          return unless room_type_name.present?

          group = groups.find { |candidate| normalized(candidate["room_type_name"]) == normalized(room_type_name) }
          return unless group

          options = options_for_group(group)
          return options.first if options.one?

          room_type_requires_option_number_result(group["room_type_name"])
        end

        def groups
          @groups ||= suggested_options.select { |group| group.is_a?(Hash) }
        end

        def candidate_groups
          return groups unless resolved_room_type_name.present?

          groups.select { |group| normalized(group["room_type_name"]) == normalized(resolved_room_type_name) }
        end

        def flattened_options
          @flattened_options ||= groups.flat_map { |group| group.fetch("options", []) }
        end

        def options_for_group(group)
          options = group.fetch("options", [])
          return options unless pending_selection_check_in.present?

          options.select { |option| option["check_in"] == pending_selection_check_in }
        end

        def narrow_by_room_type(matches)
          return matches unless resolved_room_type_name.present?

          matches.select { |option| normalized(option["room_type_name"]) == normalized(resolved_room_type_name) }
        end

        def mentioned_room_type_name(candidate_groups)
          exact_match = candidate_groups.find do |group|
            normalized_message.include?(normalized(group["room_type_name"]))
          end
          return exact_match.fetch("room_type_name") if exact_match

          partial_matches = candidate_groups.select do |group|
            room_type_match_score(group["room_type_name"]).positive?
          end

          if partial_matches.many?
            best_score = partial_matches.map { |group| room_type_match_score(group["room_type_name"]) }.max
            partial_matches = partial_matches.select { |group| room_type_match_score(group["room_type_name"]) == best_score }
          end

          return partial_matches.first.fetch("room_type_name") if partial_matches.one?

          nil
        end

        def resolved_room_type_name
          @resolved_room_type_name ||= mentioned_room_type_name(groups) || pending_selection["room_type_name"]
        end

        def pending_selection_check_in
          pending_selection["check_in"].to_s.presence
        end

        def ambiguous_option_result(candidate_groups)
          {
            "success" => false,
            "error" => "ambiguous_option_selection",
            "room_type_names" => candidate_groups.map { |group| group["room_type_name"] },
            "option_number" => resolved_option_number
          }
        end

        def ambiguous_date_result(matches)
          {
            "success" => false,
            "error" => "ambiguous_date_selection",
            "room_type_names" => matches.map { |option| option["room_type_name"] }.uniq,
            "check_in" => check_in
          }
        end

        def room_type_requires_option_number_result(room_type_name)
          {
            "success" => false,
            "error" => "room_type_requires_option_number",
            "room_type_name" => room_type_name,
            "check_in" => pending_selection_check_in || check_in
          }
        end

        def normalized(value)
          value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish
        end

        def normalized_message
          @normalized_message ||= normalized(message)
        end

        def message_tokens
          @message_tokens ||= normalized_message.split
        end

        def room_type_match_score(room_type_name)
          room_tokens = significant_tokens(room_type_name)
          return 0 if room_tokens.empty? || room_type_message_tokens.empty?

          return 4 if consecutive_token_match?(room_tokens)
          return 3 if all_tokens_prefix_match?(room_tokens)
          return 2 if all_tokens_fuzzy_match?(room_tokens)

          0
        end

        def consecutive_token_match?(room_tokens)
          max_start = room_tokens.length - room_type_message_tokens.length
          return false if max_start.negative?

          (0..max_start).any? do |start_index|
            room_type_message_tokens.each_with_index.all? do |token, offset|
              room_tokens[start_index + offset].start_with?(token)
            end
          end
        end

        def all_tokens_prefix_match?(room_tokens)
          room_type_message_tokens.all? do |token|
            room_tokens.any? { |room_token| room_token.start_with?(token) || token.start_with?(room_token) }
          end
        end

        def all_tokens_fuzzy_match?(room_tokens)
          return false if room_type_message_tokens.size > room_tokens.size

          room_type_message_tokens.all? do |token|
            room_tokens.any? { |room_token| small_typo_match?(token, room_token) }
          end
        end

        def room_type_message_tokens
          @room_type_message_tokens ||= significant_tokens(message).reject do |token|
            ROOM_TYPE_IGNORED_TOKENS.include?(token) || token.match?(/^\d+$/)
          end
        end

        def significant_tokens(value)
          normalized(value).split.filter_map do |token|
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

        def resolved_option_number
          @resolved_option_number ||= begin
            extracted = explicit_numeric_option
            extracted.present? ? extracted.to_i : option_number
          end
        end

        def explicit_numeric_option
          normalized_message[/\b(?:option|number|choice)\s*(\d+)\b/, 1] ||
            normalized_message[/\b(?:choose|chose|picked|pick|take|go with)\s+(?:option\s*)?(\d+)\b/, 1]
        end
      end
    end
  end
end

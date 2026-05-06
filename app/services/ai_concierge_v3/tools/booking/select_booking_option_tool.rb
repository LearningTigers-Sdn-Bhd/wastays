module AiConciergeV3
  module Tools
    module Booking
      class SelectBookingOptionTool
        ROOM_TYPE_IGNORED_TOKENS = %w[
          a an and book booking can choice choose chose for go i in is me my number ok on option pick picked please room suite take the this to villa want with
          jan january feb february mar march apr april may jun june jul july aug august sep september oct october nov november dec december
          first second third one two three four five six seven eight nine ten
        ].freeze

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
            room_type_tokens_match?(group["room_type_name"])
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

        def room_type_tokens_match?(room_type_name)
          room_tokens = normalized(room_type_name).split
          return false if room_tokens.empty? || room_type_message_tokens.empty?

          consecutive_token_match?(room_tokens) || all_tokens_prefix_match?(room_tokens)
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
            room_tokens.any? { |room_token| room_token.start_with?(token) }
          end
        end

        def room_type_message_tokens
          @room_type_message_tokens ||= message_tokens.reject do |token|
            ROOM_TYPE_IGNORED_TOKENS.include?(token) || token.match?(/^\d+$/)
          end
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

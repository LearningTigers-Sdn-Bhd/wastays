module AiConcierge
  module Tools
    module Booking
      class SelectBookingOptionTool
        def initialize(option_number:, suggested_options:, suggestion_set_version: nil, selection_id: nil, message: nil)
          @option_number = option_number.to_i
          @suggested_options = Array(suggested_options)
          @suggestion_set_version = suggestion_set_version
          @selection_id = selection_id.to_s.presence
          @message = message.to_s
        end

        def call
          option = selected_option
          return ({ "success" => false, "error" => "invalid_selection" }) unless option

          {
            "success" => true,
            "selected_option" => option,
            "suggestion_set_version" => suggestion_set_version
          }
        end

        private

        attr_reader :option_number, :suggested_options, :suggestion_set_version, :selection_id, :message

        # A row of the catalogue, and nothing else.
        #
        # The catalogue numbers every option in one run across all room types
        # (SearchBookingOptionsTool#numbered), so a position names exactly one
        # option. That is the whole matcher: there is nothing a room name could
        # disambiguate that the number has not already decided, and a name only
        # ever guessed. A guest who sends one is told to send the number.
        #
        # `selection_id` is the key a saved selection resumes by, so it is read
        # first and read exactly.
        def selected_option
          candidates = flattened_options
          candidates = narrow(candidates) { |option| option["selection_id"] == selection_id } if selection_id.present?
          candidates = narrow(candidates) { |option| option["position"].to_i == resolved_option_number } if resolved_option_number.positive?

          candidates.first if candidates.one?
        end

        # A signal that matches nothing is stale, not decisive: it leaves the
        # list it was given, and the answer falls to whatever else narrowed it.
        def narrow(candidates)
          candidates.select { |option| yield(option) }.presence || candidates
        end

        def groups
          @groups ||= suggested_options.select { |group| group.is_a?(Hash) }
        end

        # The room type is a property of the group, and only sometimes repeated
        # on the option. Carried down here so the confirmation and the quote can
        # name the room without looking back up at its group.
        def flattened_options
          @flattened_options ||= groups.flat_map do |group|
            group.fetch("options", []).map do |option|
              option.merge("room_type_name" => group["room_type_name"].presence || option["room_type_name"])
            end
          end
        end

        # The number the guest wrote wins over the one the model passed: it is
        # the same list they are both looking at, and only one of them read it.
        def resolved_option_number
          @resolved_option_number ||= option_reference.number || option_number
        end

        def option_reference
          @option_reference ||= Matching::OptionReference.new(message: message)
        end
      end
    end
  end
end

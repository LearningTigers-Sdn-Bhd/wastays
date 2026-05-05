module AiConciergeV3
  module MessageBuilders
    class BookingActionsBuilder < BaseBuilder
      HANDLED_REPLY_TYPES = %i[
        greeting
        reset
        ask_booking_timing
        ask_duration
        ask_guest_count
        ask_adult_count
        ask_party_split
        suggest_options
        resume_options
        ask_confirmation
        decline_confirmation
        invalid_selection
        ambiguous_option_selection
        ambiguous_date_selection
        room_type_requires_option_number
        booking_link_ready
        no_options
      ].freeze

      def call(reply_type)
        case reply_type.to_sym
        when :greeting
          "Hello, welcome to #{hotel.name}! I can help with bookings, stay details, and more about the hotel. What would you like to inquire about?"
        when :reset
          "Sure, let's start over. What dates or month would you like to book?"
        when :ask_booking_timing
          "What dates or month would you like to check in?"
        when :ask_duration
          "How many days and nights will you be staying?"
        when :ask_guest_count
          ask_guest_count_message
        when :ask_adult_count
          "How many adults will be staying?"
        when :ask_party_split
          "For #{context[:party_size_total]} people, how many are adults and how many are children?"
        when :suggest_options
          suggest_options_message
        when :resume_options
          "Here are the booking options we saved for you:\n\n#{suggest_options_message}"
        when :ask_confirmation
          ask_confirmation_message
        when :decline_confirmation
          "No problem. Please tell me the room type name and option number you would like instead."
        when :invalid_selection
          "I couldn't match that option. Please tell me the room type name and option number from the list I shared."
        when :ambiguous_option_selection
          ambiguous_option_selection_message
        when :ambiguous_date_selection
          ambiguous_date_selection_message
        when :room_type_requires_option_number
          room_type_requires_option_number_message
        when :booking_link_ready
          booking_link_ready_message
        when :no_options
          no_options_message
        end
      end

      private

      def ask_guest_count_message
        label = context[:month_label].presence
        suffix = label ? " in #{label}" : ""
        "How many guests should I check for#{suffix}?"
      end

      def suggest_options_message
        groups = Array(context[:options])
        intro = "Here are the available options"
        intro = "#{intro} for #{context[:guest_label]}" if context[:guest_label].present?
        intro = "#{intro} in #{context[:month_label]}" if context[:month_label].present?

        sections = groups.map { |group| option_group_lines(group) }

        [
          "#{intro}:",
          sections.join("\n\n"),
          'Reply with the room type name and option number or date you want, for example: "Ocean Villa King option 1" or "Executive Penthouse on May 21".'
        ].join("\n\n")
      end

      def ask_confirmation_message
        option = context[:selected_option] || {}
        "You'd like #{option['room_type_name']} from #{format_date(option['check_in'])} to #{format_date(option['check_out'])} for #{format_price(option['currency'], option['total_price'])}. Please reply *Yes* or *No*."
      end

      def ambiguous_option_selection_message
        "I found option #{context[:option_number]} under #{join_names(context[:room_type_names])}. Please tell me the room type name and option number."
      end

      def ambiguous_date_selection_message
        "I found #{format_date(context[:check_in])} under #{join_names(context[:room_type_names])}. Please tell me which room type you want."
      end

      def room_type_requires_option_number_message
        lines = ["I found multiple options under #{context[:room_type_name]}:"]
        lines << option_group_lines(context[:room_options]) if context[:room_options].present?
        lines << "Please tell me the option number you want."
        lines.join("\n\n")
      end

      def booking_link_ready_message
        result = context[:result] || {}
        selected_option = result["selected_option"] || {}

        "Great, I've prepared your booking link for #{format_date_range(selected_option['check_in'], selected_option['check_out'])}. Total: #{format_price(result['currency'], result['total_amount'])}. This link expires at #{format_time(result['expires_at'])}. Book here: #{result['booking_url']}"
      end

      def no_options_message
        label = context[:month_label].presence || "those dates"
        "Sorry, I couldn't find any rooms available for #{label}. If you want, send another date or month and I'll check again."
      end
    end
  end
end

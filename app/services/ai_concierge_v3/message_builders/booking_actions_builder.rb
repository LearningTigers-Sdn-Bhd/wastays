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
        ask_specific_timing
      ].freeze

      def call(reply_type)
        case reply_type.to_sym
        when :greeting
          "Hello, welcome to #{hotel.name}! I can help with bookings, stay details, and more about the hotel. What would you like to inquire about?"
        when :reset
          "Sure, let's start over. What dates or month would you like to book?"
        when :ask_booking_timing
          "Sure, what dates or month would you like to check in?"
        when :ask_specific_timing
          ask_specific_timing_message
        when :ask_duration
          "How many days and nights will you be staying?"
        when :ask_guest_count
          ask_guest_count_message
        when :ask_adult_count
          "How many adults will be staying?"
        when :ask_party_split
          ask_party_split_message
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
        check_in = context[:check_in]
        suffix = if check_in.present?
                   " on #{format_date(check_in)}"
                 elsif context[:month_label].present?
                   " in #{context[:month_label]}"
                 else
                   ""
                 end
        "How many guests should I check for#{suffix}?"
      end

      def ask_specific_timing_message
        "You want to make a booking in #{context[:month_label]}. May I know the exact check-in date or assumption range, e.g: *early*, *mid*, and *late*?"
      end

      def ask_party_split_message
        total = context[:party_size_total].to_i
        adults = context[:adults]
        children = context[:children]

        if adults.present? && adults.to_i.positive? && adults.to_i < total
          remaining = total - adults.to_i
          "I've noted #{adults} adults. For the remaining #{remaining} #{'person'.pluralize(remaining)}, are they children? Please reply *Yes* to confirm, or let me know the correct number of adults and children."
        elsif children.present? && children.to_i.positive? && children.to_i < total
          remaining = total - children.to_i
          "I've noted #{children} children. For the remaining #{remaining} #{'person'.pluralize(remaining)}, are they adults? Please reply *Yes* to confirm, or let me know the correct number of adults and children."
        else
          "For #{total} people, how many are adults and how many are children?"
        end
      end

      def suggest_options_message
        groups = Array(context[:options])
        intro = "Here are the available options"
        intro = "#{intro} for #{context[:guest_label]}" if context[:guest_label].present?
        intro = "#{intro} in #{context[:month_label]}" if context[:month_label].present?

        sections = groups.map { |group| option_group_lines(group) }
        url = public_hotel_url(context[:search_params] || {})

        [
          "#{intro}:",
          sections.join("\n\n"),
          'Reply with the room type name and option number or date you want, for example: "Ocean Villa King option 1" or "Executive Penthouse on May 21"',
          "You may visit this link for more details:\n#{url}"
        ].join("\n\n")
      end

      def ask_confirmation_message
        option = context[:selected_option] || {}
        room = hotel.room_types.find_by(id: option["room_type_id"])
        description = room&.description.presence || "No description available."
        amenity_lines = Array(room&.amenities).map do |a_id|
          name = Hotel::ROOM_AMENITIES.find { |ra| ra[:id] == a_id }&.dig(:name)
          "- #{name}" if name.present?
        end.compact

        [
          "Would you like to confirm your quotation for this room start from #{format_full_date(option['check_in'])} until #{format_full_date(option['check_out'])} for #{format_price(option['currency'], option['total_price'])}.",
          "",
          "*#{option['room_type_name']}*",
          description,
          "",
          "Room Amenities:",
          amenity_lines.presence&.join("\n") || "- Standard amenities",
          "",
          "Please reply *Yes* to confirm the book and *No* to reconsider the choices."
        ].join("\n")
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

        [
          "Great, I've prepared your booking quote:",
          "- Date: *#{format_full_date_range(selected_option['check_in'], selected_option['check_out'])}*",
          "- Total: *#{format_price(result['currency'], result['total_amount'])}*",
          "",
          "Please note that the quotation link will expire at #{format_time(result['expires_at'])}.",
          "Quotation link:",
          result["booking_url"],
          "",
          "Please let me know if you need anything."
        ].join("\n")
      end

      def no_options_message
        label = context[:month_label].presence || "those dates"
        "Sorry, I couldn't find any rooms available for #{label}. If you want, send another date or month and I'll check again."
      end
    end
  end
end

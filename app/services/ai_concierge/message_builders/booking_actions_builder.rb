module AiConcierge
  module MessageBuilders
    class BookingActionsBuilder < BaseBuilder
      HANDLED_REPLY_TYPES = %i[
        greeting
        reset
        ask_booking_timing
        ask_room_rate_timing
        timing_in_the_past
        ask_date_range_month
        ask_duration
        ask_guest_count
        ask_adult_count
        ask_party_split
        suggest_options
        resume_options
        ask_confirmation
        decline_confirmation
        invalid_selection
        booking_link_ready
        no_options
        ask_specific_timing
        ask_rate_plan
        confirm_to_end_conversation
        booking_attempt_cancelled_next_step
        end_conversation_declined
      ].freeze

      def call(reply_type)
        case reply_type.to_sym
        when :greeting
          "Hello, welcome to #{hotel.name}! I can help with bookings, stay details, and more about the hotel. What would you like to inquire about?"
        when :reset
          "Sure, let's start over. What dates or month would you like to book?"
        when :ask_booking_timing
          ask_booking_timing_message
        when :ask_room_rate_timing
          "Dear guest, room rates depend on the booking dates and room types. Which date or month do you plan to arrive for check-in?"
        when :timing_in_the_past
          timing_in_the_past_message
        when :ask_date_range_month
          "You said #{context[:date_range_label]}, but which month?"
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
          "No problem. Please tell me the number of the option you would like instead."
        when :invalid_selection
          %(I couldn't match that. Please reply with the number from the list, e.g. "1".)
        when :booking_link_ready
          booking_link_ready_message
        when :no_options
          no_options_message
        when :ask_rate_plan
          ask_rate_plan_message
        when :confirm_to_end_conversation
          confirm_to_end_conversation_message
        when :booking_attempt_cancelled_next_step
          booking_attempt_cancelled_next_step_message
        when :end_conversation_declined
          end_conversation_declined_message
        end
      end

      private

      TIMING_QUESTION = "Which date or month do you plan to arrive for check-in?"

      # One question, and a sentence in front of it that answers what the guest
      # actually said.
      #
      # Three things vary and nothing else: whether the hotel has spoken in
      # this thread yet, and whether the guest asked *how* to book rather than
      # asking to book. Written as combinations these are four near-identical
      # sentences that drift apart the first time one is edited, so the
      # question is stated once and only its opening changes.
      def ask_booking_timing_message
        return "Sure, #{TIMING_QUESTION.downcase_first}" if timing_preface.blank?

        "#{timing_preface} #{TIMING_QUESTION}"
      end

      def timing_preface
        [ ("Hello!" if context[:opening_reply]), timing_offer ].compact.join(" ")
      end

      # What the hotel can do about it, said before anything is asked back.
      # "How do I book?" is answered by "you book here, with me" -- which is
      # true of a plain booking request too, just less necessary to say.
      def timing_offer
        return "I can help you book right here." if context[:how_to_question]

        "I can help you with your booking." if context[:opening_reply]
      end

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

        url = public_hotel_url(context[:search_params] || {})

        [
          "#{intro}:",
          search_summary_line,
          option_catalogue_lines(groups),
          selection_instruction(groups),
          "You may visit this link for more details:\n#{url}"
        ].compact_blank.join("\n\n")
      end

      # The example is taken from the list the guest is looking at, so the one
      # answer offered is one that will actually match. The number is the only
      # answer the catalogue accepts -- a room name is not a second way in.
      def selection_instruction(groups)
        first = catalogue_options(groups).first
        return "Reply with the number of the option you want." if first.blank?

        %(Reply with the number of the option you want, e.g. "#{first['position']}".)
      end

      # What the search actually ran on, spelled out before any price. A party
      # size the guest never gave is invisible until it is written down.
      def search_summary_line
        params = context[:search_params]
        return if params.blank?

        check_in = params["check_in"]
        check_out = params["check_out"]
        rooms = params["room_count"].to_i

        nights = nights_between(check_in, check_out).to_i

        parts = []
        parts << format_full_date_range(check_in, check_out) if check_in.present? && check_out.present?
        parts << "#{nights} #{'night'.pluralize(nights)}" if nights.positive?
        parts << context[:guest_label] if context[:guest_label].present?
        parts << "#{rooms} #{'room'.pluralize(rooms)}" if rooms.positive?
        return if parts.empty?

        "_#{parts.join(' · ')}_"
      end

      def nights_between(check_in, check_out)
        return if check_in.blank? || check_out.blank?

        (Date.parse(check_out.to_s) - Date.parse(check_in.to_s)).to_i
      rescue Date::Error
        nil
      end

      def ask_confirmation_message
        option = context[:selected_option] || {}
        rate_plan = option["selected_rate_plan"] || {}
        room = hotel.room_types.find_by(id: option["room_type_id"])
        description = room&.description.presence || "No description available."
        amenity_lines = Array(room&.amenities).map do |a_id|
          name = Hotel::ROOM_AMENITIES.find { |ra| ra[:id] == a_id }&.dig(:name)
          "- #{name}" if name.present?
        end.compact

        price = rate_plan["total_price"].presence || option["total_price"]
        currency = rate_plan["currency"].presence || option["currency"]
        rate_plan_suffix = rate_plan["name"].present? ? " (#{rate_plan['name']})" : ""

        [
          "Would you like to confirm your quotation for this room start from #{format_full_date(option['check_in'])} until #{format_full_date(option['check_out'])} for #{format_price(currency, price)}#{rate_plan_suffix}.",
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

      # Naming the date is the whole point: the guest wrote a year, or the
      # model read one, and until somebody says it out loud they have no way to
      # know which date the hotel is looking at.
      def timing_in_the_past_message
        date = context[:check_in]
        return "That date has already passed. Which date or month would you like to check in?" if date.blank?

        "#{format_full_date(date)} has already passed. Which date or month would you like to check in?"
      end

      def no_options_message
        label = context[:month_label].presence || "those dates"
        "Sorry, I couldn't find any rooms available for #{label}. If you want, send another date or month and I'll check again."
      end

      def ask_rate_plan_message
        option = context[:selected_option] || {}
        rate_plans = Array(context[:rate_plans])

        date_range = "#{format_full_date(option['check_in'])} - #{format_full_date(option['check_out'])}"
        rate_lines = rate_plans.each_with_index.map do |rp, i|
          "#{i + 1}. #{format_option_price(rp['currency'], rp['total_price'])} — #{rp['name']}"
        end

        [
          "*#{option['room_type_name']}*\n_#{date_range}_",
          "Which rate would you like?",
          rate_lines.join("\n"),
          "Please reply with the number."
        ].join("\n\n")
      end

      # One question, answerable by the one word the guest is about to send.
      #
      # This used to offer three choices in a sentence -- start over, ask about
      # policies, or end -- and then be answered by a reader that knows only
      # yes and no, so a guest who picked one of the three was heard as neither.
      # Worse, the generic wording asked whether they had anything else, where
      # "yes" means carry on, while "yes" here has always meant end.
      END_QUESTION = "Would you like to end this chat? Please reply *Yes* to end, or *No* to carry on."

      def confirm_to_end_conversation_message
        case context[:end_confirmation_mode].to_s
        when "cancel_booking_attempt", "continue_booking"
          "Your booking isn't finished yet. #{END_QUESTION}"
        else
          END_QUESTION
        end
      end

      # What "no" leaves the guest in the middle of. A booking they were part
      # way through is worth naming, so the next thing they send has somewhere
      # obvious to go.
      def end_conversation_declined_message
        case context[:end_confirmation_mode].to_s
        when "cancel_booking_attempt", "continue_booking"
          "No problem, let's carry on with your booking."
        else
          "No problem, I'm here if you need anything else."
        end
      end

      def booking_attempt_cancelled_next_step_message
        "I've cancelled your booking attempt. Would you like to start a new booking, ask about hotel policies or information, or end the conversation?"
      end
    end
  end
end

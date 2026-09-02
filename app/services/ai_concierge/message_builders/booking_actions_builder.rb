module AiConcierge
  module MessageBuilders
    class BookingActionsBuilder < BaseBuilder
      # Said before the question, not instead of it: the guest still needs the
      # list in front of them, and repeating the question word for word is what
      # made a thread feel like a wall.
      NOT_UNDERSTOOD = "Sorry, I didn't catch that."

      def call(reply_type)
        message = build(reply_type)
        return message unless context[:retry] && message.present?

        "#{NOT_UNDERSTOOD}\n\n#{message}"
      end

      def build(reply_type)
        case reply_type.to_sym
        when :ask_booking_timing
          ask_booking_timing_message
        when :ask_room_rate_timing
          "Of course. I can compare current room prices. Which date or month are you considering for check-in?"
        when :timing_in_the_past
          timing_in_the_past_message
        when :ask_date_range_month
          price_exploration? ? "You want to compare #{date_range_label}, but which month?" : "You said #{date_range_label}, but which month?"
        when :ask_specific_timing
          ask_specific_timing_message
        when :ask_duration
          price_exploration? ? price_duration_message : "How many days and nights will you be staying?"
        when :ask_guest_count
          ask_guest_count_message
        when :ask_adult_count
          price_exploration? ? %(How many adults should I include in the price comparison? Please reply with the number, e.g. "2 adults".) : %(How many adults will be staying? Please reply with the number, e.g. "2 adults".)
        when :ask_party_split
          ask_party_split_message
        when :suggest_options
          suggest_options_message
        when :price_options
          suggest_options_message
        when :resume_options
          "Here are the booking options we saved for you:\n\n#{suggest_options_message}"
        when :price_option_details
          price_option_details_message
        when :price_option_declined
          "No problem. You can compare another option or change the dates."
        when :price_option_required
          "Which priced option would you like to book? Please send its number."
        when :price_option_invalid
          "I could not match that priced option. Please send a number from the list."
        when :price_option_guidance
          "This option is still only being compared. You can view another option, change the dates, or say *book this option* when you are ready."
        when :ask_confirmation
          ask_confirmation_message
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

      # The example is the question's real content.
      #
      # Asked "how many guests", a guest who has never booked online answers
      # "me and my wife" -- true, and not a number. Nothing downstream can turn
      # that into a party size, so the answer is thrown away and the same
      # question comes back, which is how a thread turns into a wall.
      #
      # Showing the shape of the answer is cheaper than reading every shape an
      # answer might take. It also lands the guest on the one phrasing the
      # message itself can be read for -- "2 adults" and "3 children" are
      # matched straight out of the text by InputNormalizer, with no model
      # judgement in between.
      GUEST_COUNT_FORMAT = %(Please reply with the number of adults and children, e.g. "2 adults 3 children".)

      def ask_guest_count_message
        check_in = context[:check_in]
        suffix = if check_in.present?
                   " on #{format_date(check_in)}"
        elsif month_label.present?
                   " in #{month_label}"
        else
                   ""
        end
        if price_exploration?
          "How many adults and children should I include in the price comparison#{suffix}? #{GUEST_COUNT_FORMAT}"
        else
          "How many guests should I check for#{suffix}? #{GUEST_COUNT_FORMAT}"
        end
      end

      def ask_specific_timing_message
        if price_exploration?
          return price_specific_timing_message
        end

        "You want to make a booking in #{month_label}. May I know the exact check-in date or assumption range, e.g: *early*, *mid*, and *late*?"
      end

      def price_duration_message
        return "How many nights would you like me to compare?" if month_label.blank?

        "For #{month_label}, how many nights would you like me to compare?"
      end

      def price_specific_timing_message
        month = branch["target_month"].to_i
        year = branch["target_year"].to_i
        date = Date.new(year, month, 1)
        name = date.strftime("%B")
        last_day = date.end_of_month.day

        "For #{name} #{year}, should I compare early #{name} (1–10), mid-#{name} (11–20), or late #{name} (21–#{last_day})? " \
          "You can also give me exact dates."
      rescue Date::Error
        "For #{month_label}, do you prefer early, middle, or late in the month? You can also give me exact dates."
      end

      def ask_party_split_message
        total = context[:party_size_total].to_i
        adults = context[:adults]
        children = context[:children]

        return price_party_split_message(total, adults, children) if price_exploration?

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

      def price_party_split_message(total, adults, children)
        if adults.present? && adults.to_i.positive? && adults.to_i < total
          return "I have #{adults} adults. How many of the remaining #{total - adults.to_i} guests are children?"
        end
        if children.present? && children.to_i.positive? && children.to_i < total
          return "I have #{children} children. How many of the remaining #{total - children.to_i} guests are adults?"
        end

        "For the price comparison, how many of the #{total} guests are adults and how many are children?"
      end

      def suggest_options_message
        groups = Array(context[:options])
        intro = context[:price_exploration] ? "Here are the available price options" : "Here are the available options"
        intro = "#{intro} for #{guest_label}" if guest_label.present?
        intro = "#{intro} in #{month_label}" if month_label.present?

        url = public_hotel_url(context[:search_params] || {})

        [
          "#{intro}:",
          search_summary_line,
          option_catalogue_lines(groups),
          selection_instruction(groups),
          "You may visit this link for more details:\n#{url}"
        ].compact_blank.join("\n\n")
      end

      def price_option_details_message
        option = context[:selected_option] || {}
        details = context[:room_details] || {}
        rate_plans = Array(option["rate_plans"])
        amenities = Array(details["amenities"])

        lines = [
          "*#{details['room_type_name'].presence || option['room_type_name']}*",
          "_#{format_full_date_range(option['check_in'], option['check_out'])} · #{guest_label}_",
          details["description"].presence,
          occupancy_line(details),
          ("Amenities: #{amenities.join(', ')}." if amenities.present?),
          "Available rates:",
          rate_plan_lines(rate_plans, option),
          "You can compare another option, change the dates, or say *book this option* when you are ready."
        ]

        lines.compact_blank.join("\n\n")
      end

      def occupancy_line(details)
        parts = []
        parts << "#{details['max_adults']} #{'adult'.pluralize(details['max_adults'])}" if details["max_adults"].present?
        parts << "#{details['max_children']} #{'child'.pluralize(details['max_children'])}" if details["max_children"].present?
        return if parts.empty?

        "Capacity: #{parts.to_sentence}."
      end

      def rate_plan_lines(rate_plans, option)
        return "- #{format_price(option['currency'], option['total_price'])}" if rate_plans.empty?

        rate_plans.map do |rate_plan|
          "- #{rate_plan['name']}: #{format_price(rate_plan['currency'], rate_plan['total_price'])}"
        end.join("\n")
      end

      # The example is taken from the list the guest is looking at, so the one
      # answer offered is one that will actually match. The number is the only
      # answer the catalogue accepts -- a room name is not a second way in.
      def selection_instruction(groups)
        first = catalogue_options(groups).first
        if context[:price_exploration]
          return "Reply with a number to see room and rate details." if first.blank?

          return %(Reply with a number to see room and rate details, e.g. "#{first['position']}". This does not select or book the room.)
        end
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

        nights = if check_in.present? && check_out.present?
                   nights_between(check_in, check_out).to_i
        else
                   branch["nights"].to_i
        end

        parts = []
        parts << format_full_date_range(check_in, check_out) if check_in.present? && check_out.present?
        parts << "#{nights} #{'night'.pluralize(nights)}" if nights.positive?
        parts << guest_label if guest_label.present?
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
        label = month_label.presence || "those dates"
        return "I could not find a current room price for #{label}. Send another date or month, and I will compare the available options." if price_exploration?

        "I could not find a bookable room for #{label}. Send another date or month, and I will check again."
      end

      def price_exploration?
        context[:price_exploration]
      end

      def ask_rate_plan_message
        option = context[:selected_option] || {}
        rate_plans = Array(context[:rate_plans])

        date_range = "#{format_full_date(option['check_in'])} - #{format_full_date(option['check_out'])}"
        rate_lines = rate_plans.each_with_index.map do |rp, i|
          "#{i + 1}. #{format_price(rp['currency'], rp['total_price'])} — #{rp['name']}"
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
        case context[:language].to_s
        when "ms"
          "Saya telah menghentikan percubaan tempahan ini. Anda boleh mulakan tempahan baharu atau tanya tentang hotel."
        when "zh"
          "我已停止这次预订尝试。您可以开始新的预订，或询问酒店信息。"
        else
          "I stopped this booking attempt. You can start a new booking or ask about the hotel."
        end
      end
    end
  end
end

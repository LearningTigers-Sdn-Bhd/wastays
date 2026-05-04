module AiConciergeV3
  class MessengerAgent
    def initialize(hotel:, context:)
      @hotel = hotel
      @context = context
    end

    def call
      { "reply_message" => render_message }
    end

    private

    attr_reader :hotel, :context

    def render_message
      case context[:reply_type]&.to_sym
      when :greeting
        "Hello, welcome to #{hotel.name}! I can help with bookings, stay details, and more about the hotel. What would you like to inquire about?"
      when :reset
        "Sure, let's start over. What dates or month would you like to book?"
      when :ask_booking_timing
        "What dates or month would you like to check in?"
      when :ask_duration
        "How many days and nights will you be staying?"
      when :ask_guest_count
        label = context[:month_label].presence
        suffix = label ? " in #{label}" : ""
        "How many guests should I check for#{suffix}?"
      when :ask_adult_count
        "How many adults will be staying?"
      when :ask_party_split
        "For #{context[:party_size_total]} people, how many are adults and how many are children?"
      when :suggest_options
        suggest_options_message
      when :resume_options
        "Here are the booking options we saved for you:\n\n#{suggest_options_message}"
      when :ask_confirmation
        option = context[:selected_option] || {}
        "You'd like #{option['room_type_name']} from #{format_date(option['check_in'])} to #{format_date(option['check_out'])} for #{format_price(option['currency'], option['total_price'])}. Please reply *Yes* or *No*."
      when :decline_confirmation
        "No problem. Please tell me the room type name and option number you would like instead."
      when :invalid_selection
        "I couldn't match that option. Please tell me the room type name and option number from the list I shared."
      when :ambiguous_option_selection
        "I found option #{context[:option_number]} under #{join_names(context[:room_type_names])}. Please tell me the room type name and option number."
      when :ambiguous_date_selection
        "I found #{format_date(context[:check_in])} under #{join_names(context[:room_type_names])}. Please tell me which room type you want."
      when :room_type_requires_option_number
        room_type_requires_option_number_message
      when :booking_link_ready
        booking_link_ready_message
      when :no_options
        label = context[:month_label].presence || "those dates"
        "Sorry, I couldn't find any rooms available for #{label}. If you want, send another date or month and I'll check again."
      when :hotel_policy
        hotel_policy_message
      when :booking_context
        booking_context_message
      else
        context[:message].presence || FallbackBuilder::DEFAULT_MESSAGE
      end
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

    def booking_link_ready_message
      result = context[:result] || {}
      selected_option = result["selected_option"] || {}

      "Great, I've prepared your booking link for #{format_date_range(selected_option['check_in'], selected_option['check_out'])}. Total: #{format_price(result['currency'], result['total_amount'])}. This link expires at #{format_time(result['expires_at'])}. Book here: #{result['booking_url']}"
    end

    def hotel_policy_message
      result = context[:result] || {}
      [
        "Welcome to #{hotel.name}! Here is our hotel policy:",
        "- Check-in starts at: *#{result['check_in_time']}*",
        "- Check-out is at: *#{result['check_out_time']}*",
        "- Cancellation: *#{result['cancellation_policy']}*"
      ].join("\n")
    end

    def booking_context_message
      bookings = Array(context[:bookings])
      return "According to our system, we could not find an active booking at the moment." if bookings.empty?

      intro = bookings.one? ? "According to our system, we found your active booking:" : "According to our system, we found your active bookings:"
      lines = bookings.map do |booking|
        "- *#{booking['date_range']}*: #{booking['room_type_name']}"
      end

      [intro, lines.join("\n")].join("\n")
    end

    def room_type_requires_option_number_message
      lines = ["I found multiple options under #{context[:room_type_name]}:"]
      lines << option_group_lines(context[:room_options]) if context[:room_options].present?
      lines << "Please tell me the option number you want."
      lines.join("\n\n")
    end

    def option_group_lines(group)
      return "" unless group.is_a?(Hash)

      lines = Array(group["options"]).map do |option|
        "#{option['position']}. #{format_option_price(option['currency'], option['total_price'])} : Check-in *#{format_date(option['check_in'])}* - Check-out *#{format_date(option['check_out'])}*"
      end

      [group["room_type_name"], lines.join("\n")].join("\n")
    end

    def format_date(value)
      return value.to_s if value.blank?

      Date.parse(value.to_s).strftime("%B %-d")
    rescue Date::Error
      value.to_s
    end

    def format_date_range(check_in, check_out)
      return "your selected stay" if check_in.blank? || check_out.blank?

      "#{format_date(check_in)} to #{format_date(check_out)}"
    end

    def format_price(currency, amount)
      [display_currency(currency), format("%.2f", amount.to_f)].join(" ")
    end

    def format_option_price(currency, amount)
      format_price(currency, amount)
    end

    def display_currency(currency)
      value = currency.presence || hotel.try(:default_currency) || "MYR"
      value == "MYR" ? "RM" : value
    end

    def format_time(value)
      return value.to_s if value.blank?

      Time.zone.parse(value.to_s).strftime("%-I:%M %p")
    rescue ArgumentError
      value.to_s
    end

    def join_names(names)
      Array(names).uniq.to_sentence(two_words_connector: " and ", last_word_connector: ", and ")
    end
  end
end

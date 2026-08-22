module AiConcierge
  module MessageBuilders
    class HotelInfoBuilder < BaseBuilder
      def call(reply_type)
        case reply_type.to_sym
        when :hotel_policy
          hotel_policy_message
        when :booking_context
          booking_context_message
        when :general_hotel_info
          general_hotel_info_message
        when :hotel_faq
          hotel_faq_message
        when :nearby_attractions
          nearby_attractions_message
        end
      end

      private

      def hotel_policy_message
        result = context[:result] || {}
        return result["answer"] if result["answer"].present? && result["success"] != false
        return "Welcome to #{hotel.name}! #{result['policy_text']}" if result["policy_text"].present?

        structured_policy_present = result["check_in_time"].present? || result["check_out_time"].present? || result["cancellation_policy"].present?
        return "Welcome to #{hotel.name}! The hotel has not provided its policy details yet." unless structured_policy_present

        [
          "Welcome to #{hotel.name}! Here is our hotel policy:",
          "- Check-in starts at: *#{result['check_in_time'].presence || 'not provided yet'}*",
          "- Check-out is at: *#{result['check_out_time'].presence || 'not provided yet'}*",
          "- Cancellation: *#{result['cancellation_policy'].presence || 'The hotel has not provided that information yet.'}*"
        ].join("\n")
      end

      def booking_context_message
        bookings = Array(context[:bookings])
        return "According to our system, we could not find an active booking at the moment." if bookings.empty?

        intro = bookings.one? ? "According to our system, we found your active booking:" : "According to our system, we found your active bookings:"
        lines = bookings.map do |booking|
          dates = [ booking["check_in"], booking["check_out"] ].map { |date| format_date(date) }.join(" - ")
          "- *#{dates}*: #{booking['room_type_name']}"
        end

        [ intro, lines.join("\n") ].join("\n")
      end

      def general_hotel_info_message
        result = context[:result] || {}
        return result["answer"] if result["answer"].present? && result["success"] != false
        summary = result["summary_text"].presence
        amenities = Array(result["amenities"])
        return "I couldn't find general hotel information right now." if summary.blank? && amenities.blank?

        lines = []
        lines << summary if summary.present?
        lines << "Hotel amenities: #{amenities.join(', ')}" if amenities.present?
        lines.join("\n")
      end

      def hotel_faq_message
        result = context[:result] || {}
        return result["answer"] if result["answer"].present? && result["success"] != false
        return result["faq_text"] if result["faq_text"].present?

        "The hotel has not provided FAQ details yet."
      end

      def nearby_attractions_message
        attractions = Array(context.dig(:result, "attractions") || context[:attractions])
        return "I couldn't find any nearby attractions listed right now." if attractions.empty?

        lines = attractions.map do |attraction|
          details = [ attraction["description"], attraction["address"], attraction["city"], attraction["country"] ].compact_blank.join(". ")
          details.present? ? "- *#{attraction['name']}*: #{details}" : "- *#{attraction['name']}*"
        end

        [ "Here are the nearby attractions:", lines.join("\n") ].join("\n")
      end
    end
  end
end

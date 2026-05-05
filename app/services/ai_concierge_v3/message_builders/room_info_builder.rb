module AiConciergeV3
  module MessageBuilders
    class RoomInfoBuilder < BaseBuilder
      HANDLED_REPLY_TYPES = %i[room_type_details room_type_faq ambiguous_room_type room_type_not_found].freeze

      def call(reply_type)
        case reply_type.to_sym
        when :room_type_details
          room_type_details_message
        when :room_type_faq
          room_type_faq_message
        when :ambiguous_room_type
          ambiguous_room_type_message
        when :room_type_not_found
          room_type_not_found_message
        end
      end

      private

      def room_type_details_message
        result = context[:result] || {}
        amenities = Array(result["amenities"])
        lines = ["Here are the details for #{result['room_type_name']}:"]
        lines << result["description"] if result["description"].present?

        occupancy = []
        occupancy << "#{result['max_adults']} adult#{'s' unless result['max_adults'].to_i == 1}" if result["max_adults"].present?
        occupancy << "#{result['max_children']} child#{'ren' unless result['max_children'].to_i == 1}" if result["max_children"].present?
        lines << "Occupancy: #{occupancy.join(' and ')}" if occupancy.present?
        lines << "Amenities: #{amenities.join(', ')}" if amenities.present?
        lines.join("\n")
      end

      def room_type_faq_message
        result = context[:result] || {}
        return "Here is the FAQ for #{result['room_type_name']}:\n#{result['faq_text']}" if result["faq_text"].present?

        "The hotel has not provided FAQ details for #{result['room_type_name']} yet."
      end

      def ambiguous_room_type_message
        names = Array(context.dig(:result, "room_type_names") || context[:room_type_names])
        "I found multiple room types matching your request: #{join_names(names)}. Please tell me which room type you mean."
      end

      def room_type_not_found_message
        "I couldn't match that room type. Please tell me the room type name you want to ask about."
      end
    end
  end
end

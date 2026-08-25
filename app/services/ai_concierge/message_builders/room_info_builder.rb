module AiConcierge
  module MessageBuilders
    class RoomInfoBuilder < BaseBuilder
      def call(reply_type)
        case reply_type.to_sym
        when :room_type_details
          room_type_details_message
        when :ambiguous_room_type
          ambiguous_room_type_message
        when :room_type_not_found
          room_type_not_found_message
        end
      end

      private

      def room_type_details_message
        result = context[:result] || {}
        return result["answer"] if result["answer"].present?

        compose(result)
      end

      def ambiguous_room_type_message
        return context.dig(:result, "answer") if context.dig(:result, "answer").present?

        compose(context[:result] || {})
      end

      def room_type_not_found_message
        return context.dig(:result, "answer") if context.dig(:result, "answer").present?

        compose(context[:result] || {})
      end

      def compose(result)
        reply = Orchestration::HotelKnowledge::ReplyFactory.new(intent: "room_information", result: result).call
        Orchestration::HotelKnowledge::ReplyComposer.new(reply: reply, tone: hotel.ai_concierge_tone).call
      end
    end
  end
end

module AiConcierge
  module Orchestration
    module Turn
      class BookingContextHandler
        def initialize(hotel:, phone:, conversation: nil)
          @hotel = hotel
          @phone = phone.to_s.presence
          @conversation = conversation
        end

        def call(prospect:, conversation_state:)
          return web_booking_context(conversation_state) if anonymous_web?(prospect)

          result = Tools::HotelInformation::GetBookingContextTool.new(hotel: hotel, phone: phone || prospect.phone_number).call

          Core::DomainResponse.new(
            slots_payload: conversation_state.slots_payload,
            reply_type: :booking_context,
            extra_context: result.symbolize_keys
          )
        end

        private

        attr_reader :hotel, :phone, :conversation

        def anonymous_web?(prospect)
          conversation&.channel == "web" && phone.blank? && prospect.phone_number.blank?
        end

        def web_booking_context(conversation_state)
          manager = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload)
          Core::DomainResponse.new(
            slots_payload: manager.offer_existing_booking_portal(
              request_kind: :portal_general,
              conversation_id: conversation.id
            ),
            reply_type: :existing_booking_portal,
            active_topic: "existing_booking",
            active_flow: "existing_booking"
          )
        end
      end
    end
  end
end

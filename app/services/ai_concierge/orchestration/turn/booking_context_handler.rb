module AiConcierge
  module Orchestration
    module Turn
      class BookingContextHandler
        def initialize(hotel:, phone:)
          @hotel = hotel
          @phone = phone.to_s.presence
        end

        def call(prospect:, conversation_state:)
          result = Tools::HotelInformation::GetBookingContextTool.new(hotel: hotel, phone: phone || prospect.phone_number).call

          Core::DomainResponse.new(
            slots_payload: conversation_state.slots_payload,
            reply_type: :booking_context,
            extra_context: result.symbolize_keys
          )
        end

        private

        attr_reader :hotel, :phone
      end
    end
  end
end

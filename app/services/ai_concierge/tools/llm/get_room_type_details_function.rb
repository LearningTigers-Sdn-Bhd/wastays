# frozen_string_literal: true

module AiConcierge
  module Tools
    module Llm
      class GetRoomTypeDetailsFunction < BaseFunction
        description <<~DESCRIPTION
          Describe one of the hotel's room types: what is in it, how many people
          it sleeps, its amenities.

          Use this when the guest wants to know what a room is like. If they
          want to know what it costs, or whether it is free on their dates, use
          advance_booking instead -- both of those depend on dates.

          "Room service" is a hotel service, not a room type: that is
          answer_hotel_question.
        DESCRIPTION

        # The guest's question is not a parameter -- the tool already has the
        # message. Only the room type is something the model has to read.
        param :room_type_name, type: "string", required: false,
          desc: "The room type the guest named, if they named one."

        def execute(room_type_name: nil)
          return advance_booking_instead if rate_question?

          domain_result = Orchestration::HotelKnowledge::Orchestrator.new(
            hotel: hotel,
            message: context.message,
            interpretation: {
              "intent" => "room_information",
              "topic" => "room_information",
              "slots" => { "room_type_name" => room_type_name }
            },
            conversation_state: context.conversation_state,
            pause: context.info_interruption_active?,
            active_branch: context.booking_branch
          ).call

          record(domain_result, digest: { answered: true })
        end
      end
    end
  end
end

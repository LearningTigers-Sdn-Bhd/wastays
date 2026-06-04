module AiConcierge
  module Orchestration
    module Booking
      class CompletionHandler
        def initialize(hotel:, prospect:, phone:, tool_registry:)
          @hotel = hotel
          @prospect = prospect
          @phone = phone.to_s.presence
          @tool_registry = tool_registry
        end

        def call(conversation_state:, active_branch:)
          selected_option = active_branch["confirmation_candidate"] || active_branch["selected_option"]
          return booking_response(conversation_state: conversation_state, active_branch: active_branch, reply_type: :invalid_selection, pending_question: "select_option") unless selected_option

          selected_rate_plan = selected_option&.dig("selected_rate_plan") || {}
          result = tool_registry.fetch("generate_booking_url").new(
            hotel: hotel,
            selected_option: selected_option,
            guest_phone: phone || prospect.phone_number,
            rate_plan_id: selected_rate_plan["rate_plan_id"]
          ).call
          return { direct_payload: MessageBuilders::FallbackBuilder.new(message: result["error"]).call } unless result["success"]

          active_branch["selected_option"] = selected_option
          active_branch["confirmation_candidate"] = nil
          payload = booking_payload(conversation_state, active_branch, pending_question: nil, status: "completed")
          payload = State::ConversationTaskManager.new(slots_payload: payload).archive_completed_booking

          {
            slots_payload: payload,
            reply_type: :booking_link_ready,
            active_topic: nil,
            active_flow: nil,
            pending_question: nil,
            action_name: nil,
            extra_context: { result: result.merge("selected_option" => selected_option) },
            flow_status: "ended",
            end_reason: "booking_url_generated"
          }
        end

        private

        attr_reader :hotel, :prospect, :phone, :tool_registry

        def booking_response(conversation_state:, active_branch:, reply_type:, pending_question:, extra_context: {}, action_name: "request_quote")
          {
            slots_payload: booking_payload(conversation_state, active_branch, pending_question: pending_question),
            reply_type: reply_type,
            active_topic: "booking_search",
            active_flow: "booking_search",
            pending_question: pending_question,
            action_name: action_name,
            extra_context: extra_context
          }
        end

        def booking_payload(conversation_state, active_branch, pending_question:, status: nil)
          State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload).activate_booking(active_branch, pending_question: pending_question, status: status)
        end
      end
    end
  end
end

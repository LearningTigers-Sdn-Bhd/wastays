module AiConciergeV3
  module Orchestration
    class LibrarianOrchestrator
    def initialize(hotel:, message:, interpretation:, conversation_state:, pause:, active_branch: nil, tool_registry: Tools::ToolRegistry.new)
      @hotel = hotel
      @message = message.to_s
      @interpretation = interpretation
      @conversation_state = conversation_state
      @pause = pause
      @active_branch = active_branch
      @tool_registry = tool_registry
    end

    def call
      tool_result = route_tool
      domain_response(
        slots_payload: information_slots_payload,
        reply_type: tool_result[:reply_type],
        active_topic: pause ? tool_result[:active_topic] : nil,
        active_flow: pause ? tool_result[:active_flow] : nil,
        extra_context: { result: tool_result[:result] }
      )
    end

    private

    attr_reader :hotel, :message, :interpretation, :conversation_state, :pause, :active_branch, :tool_registry

    def route_tool
      case interpretation["intent"]
      when "hotel_policy"
        result = tool_registry.fetch("get_hotel_policy").new(hotel: hotel, policy_topic: interpretation["topic"], query: message).call
        { reply_type: :hotel_policy, active_topic: "hotel_policy", active_flow: "hotel_policy", result: result }
      when "hotel_information"
        tool_name, reply_type = hotel_information_tool_and_reply_type
        result = tool_registry.fetch(tool_name).new(hotel: hotel, query: message).call
        { reply_type: reply_type, active_topic: interpretation["topic"], active_flow: "hotel_information", result: result }
      when "nearby_attractions"
        result = tool_registry.fetch("get_nearby_attractions").new(hotel: hotel).call
        { reply_type: :nearby_attractions, active_topic: "nearby_attractions", active_flow: "hotel_information", result: result }
      when "room_information"
        result = tool_registry.fetch("get_room_type_details").new(
          hotel: hotel,
          query: message,
          room_type_name: interpretation.dig("slots", "room_type_name")
        ).call

        { reply_type: room_reply_type(result), active_topic: interpretation["topic"], active_flow: "room_information", result: result }
      else
        { reply_type: nil, active_topic: nil, active_flow: nil, result: {} }
      end
    end

    def information_slots_payload
      manager = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload)
      payload = if pause
        booking_payload = manager.activate_booking(
          branch_for_suspension,
          pending_question: manager.booking_pending_question || conversation_state.pending_question
        )
        State::ConversationTaskManager.new(slots_payload: booking_payload).suspend_booking_for_information(
          intent: interpretation["intent"],
          topic: interpretation["topic"],
          pending_question: manager.booking_pending_question || conversation_state.pending_question
        )
      else
        manager.payload
      end

      State::ConversationTaskManager.new(slots_payload: payload).update_information_task(
        intent: interpretation["intent"],
        topic: interpretation["topic"],
        question: message
      )
    end

    def branch_for_suspension
      active_branch.is_a?(Hash) ? active_branch : State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload).booking_branch
    end

    def domain_response(slots_payload:, reply_type:, active_topic: nil, active_flow: nil, pending_question: nil, action_name: nil, extra_context: {}, flow_status: nil, end_reason: nil)
      {
        slots_payload: slots_payload,
        reply_type: reply_type,
        active_topic: active_topic,
        active_flow: active_flow,
        pending_question: pending_question,
        action_name: action_name,
        extra_context: extra_context,
        flow_status: flow_status,
        end_reason: end_reason
      }
    end

    def hotel_information_tool_and_reply_type
      case interpretation["topic"]
      when "hotel_faq"
        [ "get_hotel_faq", :hotel_faq ]
      else
        [ "get_general_hotel_info", :general_hotel_info ]
      end
    end

    def room_reply_type(result)
      if result["success"]
        :room_type_details
      elsif result["error"] == "ambiguous_room_type"
        :ambiguous_room_type
      else
        :room_type_not_found
      end
    end
    end
  end
end

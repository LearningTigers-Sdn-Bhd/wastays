module AiConcierge
  module Orchestration
    module HotelKnowledge
      class Orchestrator
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
        record_knowledge_diagnostic(tool_result[:result])
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
        ToolRouter.new(
          hotel: hotel,
          message: message,
          interpretation: interpretation,
          tool_registry: tool_registry
        ).call
      end

      def information_slots_payload
        StateHandler.new(
          conversation_state: conversation_state,
          interpretation: interpretation,
          message: message,
          pause: pause,
          active_branch: active_branch
        ).slots_payload
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

      def record_knowledge_diagnostic(result)
        DiagnosticRecorder.new(
          hotel: hotel,
          message: message,
          interpretation: interpretation,
          conversation_state: conversation_state,
          result: result
        ).call
      end
      end
    end
  end
end

module AiConcierge
  module Orchestration
    module HotelKnowledge
      class Orchestrator
      def initialize(hotel:, message:, interpretation:, conversation_state:, pause:, active_branch: nil, language: nil,
        guest_language: nil)
        @hotel = hotel
        @message = message.to_s
        @interpretation = interpretation
        @conversation_state = conversation_state
        @pause = pause
        @active_branch = active_branch
        @language = language.to_s.presence || Conversation::DEFAULT_LANGUAGE
        @guest_language = guest_language
      end

      def call
        tool_result = route_tool
        reply = ReplyFactory.new(intent: interpretation["intent"], result: tool_result[:result]).call
        pending_question = clarification_pending_question(reply, tool_result[:result])
        slots_payload = information_slots_payload(reply, tool_result[:result], pending_question: pending_question)
        manager = State::ConversationTaskManager.new(slots_payload: slots_payload)
        candidate_action = next_action(reply, manager, pending_question: pending_question, suppress_offer: false)
        selected_action = next_action(
          reply,
          manager,
          pending_question: pending_question,
          suppress_offer: manager.sales_offer_suppressed?
        )
        factual_message = ReplyComposer.new(
          reply: reply,
          tone: hotel.ai_concierge_tone,
          message: message,
          previous_reply: previous_reply
        ).call
        sales_message = Sales::NextActionRenderer.new(
          answer: factual_message,
          next_action: selected_action,
          intent: interpretation["intent"],
          missing_topic: reply.missing_topic,
          acknowledge_refusal: manager.sales_refusal_acknowledgment_pending?
        ).call
        localized = Localizer.new(hotel: hotel, reply: sales_message, language: language).call
        slots_payload = sales_slots_payload(manager, candidate_action: candidate_action, selected_action: selected_action)
        result = tool_result[:result].merge(reply.to_h).merge("answer" => localized)
        record_knowledge_diagnostic(result)
        Core::DomainResponse.new(
          slots_payload: slots_payload,
          reply_type: tool_result[:reply_type],
          active_topic: pause ? tool_result[:active_topic] : nil,
          active_flow: pause ? tool_result[:active_flow] : nil,
          next_action: selected_action,
          extra_context: {
            result: result,
            knowledge_reply: true,
            guest_language: guest_language
          }
        )
      end

      private

      attr_reader :hotel, :message, :interpretation, :conversation_state, :pause, :active_branch, :language,
        :guest_language

      def route_tool
        ToolRouter.new(hotel: hotel, message: message, interpretation: interpretation).call
      end

      def previous_reply
        conversation_state&.prospect&.prospect_messages
          &.where(direction: "outbound")
          &.order(sent_at: :desc, created_at: :desc)
          &.pick(:body)
      end

      def next_action(reply, manager, pending_question:, suppress_offer:)
        Sales::NextActionPolicy.new(
          intent: interpretation["intent"],
          outcome: next_action_outcome(reply, pending_question),
          booking_task: manager.booking_task,
          resumable_booking: manager.suspended_booking_resumable?,
          needs_human_support: false,
          suppress_offer: suppress_offer
        ).call
      end

      def next_action_outcome(reply, pending_question)
        return "clarification" if pending_question.present?
        return "unavailable" if reply.shape == "unavailable"

        "answered"
      end

      def sales_slots_payload(manager, candidate_action:, selected_action:)
        return manager.consume_sales_offer_suppression if manager.sales_offer_suppressed? && candidate_action.optional?
        return manager.record_optional_sales_offer(selected_action.kind) if selected_action.optional?

        manager.clear_optional_sales_offer
      end

      def information_slots_payload(reply, result, pending_question:)
        StateHandler.new(
          conversation_state: conversation_state,
          interpretation: interpretation,
          message: message,
          pause: pause,
          active_branch: active_branch,
          pending_question: pending_question,
          clarification_context: clarification_context(reply, result)
        ).slots_payload
      end

      def clarification_pending_question(reply, result)
        return "room_type_name" if reply.shape == "unavailable" && reply.missing_topic == "room type"
        return unless reply.shape == "clarification"
        return "room_type_choice" if result["error"] == "ambiguous_room_type"
        return "opening_hours_subject" if reply.facts.first&.topic == "opening hours"

        "policy_topic" if reply.facts.first&.topic == "policy"
      end

      def clarification_context(reply, result)
        case clarification_pending_question(reply, result)
        when "room_type_choice"
          { "choices" => Array(result["room_type_names"]) }
        when "policy_topic"
          { "choices" => [ "check-in", "check-out", "cancellation", "house rules" ] }
        when "opening_hours_subject"
          { "choices" => [ "check-in", "facility" ] }
        end
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

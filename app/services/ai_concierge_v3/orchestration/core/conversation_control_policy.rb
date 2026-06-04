module AiConciergeV3
  module Orchestration
    module Core
      class ConversationControlPolicy
      def initialize(message:, conversation_state:, interpretation:)
        @message = message.to_s
        @conversation_state = conversation_state
        @interpretation = interpretation.is_a?(Hash) ? interpretation : {}
      end

      def cancel_attempt?
        return true if normalized_message.match?(/\bcancel\b/) && normalized_message.match?(/\b(?:attempt|booking|reservation|quotation|quote)\b/)
        return true if normalized_message.match?(/\b(?:drop|forget)\b/) && normalized_message.match?(/\b(?:room|booking|reservation|quotation|quote)\b/)
        return false unless active_booking_attempt?

        normalized_message.match?(/\A(?:leave it|changed my mind|i changed my mind|not that booking|not that reservation|drop it)\z/)
      end

      def explicit_end?
        normalized_message.match?(/\A(?:stop|bye|bye bye|good bye|goodbye|thanks|thank you|that's all|thats all|end chat|end conversation|nevermind|never mind|forget|forget it|no thanks|not now|cancel attempt|cancel booking attempt|cancel quotation attempt)\z/)
      end

      def end_confirmation_yes?
        interpretation["intent"].to_s == "confirmation" && interpretation.dig("slots", "confirmation") != "no"
      end

      def end_confirmation_mode
        manager = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload)
        booking_task = manager.booking_task

        return :continue_booking if booking_task["status"] == "suspended"
        return :continue_booking if booking_task["pending_question"].present? && conversation_state.active_flow.to_s != "booking_search"
        return :cancel_booking_attempt if conversation_state.active_flow == "booking_search"

        :generic
      end

      private

      attr_reader :message, :conversation_state, :interpretation

      def active_booking_attempt?
        return true if conversation_state.active_flow == "booking_search"

        manager = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload)
        booking_task = manager.booking_task
        branch = manager.booking_branch

        booking_task["status"].present? && booking_task["status"] != "idle" ||
          booking_task["pending_question"].present? ||
          branch.except("branch_id", "room_count", "suggestion_set_version", "suggested_options").values.any?(&:present?) ||
          Array(branch["suggested_options"]).present?
      end

      def normalized_message
        @normalized_message ||= message.downcase.gsub(/[^a-z0-9']+/, " ").squish
      end
      end
    end
  end
end

module AiConcierge
  module Orchestration
    module Core
      class ConversationControlPolicy
      def initialize(message:, conversation_state:, interpretation:)
        @message = message.to_s
        @conversation_state = conversation_state
        @interpretation = interpretation.is_a?(Hash) ? interpretation : {}
      end

      def cancel_attempt?
        return true if multilingual_attempt_cancellation?
        return true if normalized_message.match?(/\bcancel\b/) && normalized_message.match?(/\b(?:attempt|quotation|quote)\b/)
        return false unless active_booking_attempt?
        return false if existing_booking_wording?
        return true if normalized_message.match?(/\A(?:drop|forget) (?:the |this )?(?:room|booking|reservation|quote|quotation)\z/)

        normalized_message.match?(/\A(?:leave it|changed my mind|i changed my mind|not that booking|not that reservation|drop it|forget it)\z/)
      end

      def wait_time_end?
        normalized_message == "codename wait time end"
      end

      def booking_progress?
        active_booking_attempt?
      end

      def explicit_end?
        normalized_message.match?(/\A(?:stop|bye|bye bye|good bye|goodbye|thanks|thank you|that's all|thats all|end chat|end conversation|nevermind|never mind|forget|forget it|no thanks|not now|cancel attempt|cancel booking attempt|cancel quotation attempt)\z/)
      end

      def end_confirmation_yes?
        confirmation_answer == "yes"
      end

      def end_confirmation_no?
        confirmation_answer == "no"
      end

      # The reading the caller passed in when it has one, and the guest's own
      # words when it does not -- so this answers the same way whether the turn
      # came through the model or straight off the wire.
      def confirmation_answer
        return interpretation.dig("slots", "confirmation") if interpretation["intent"].to_s == "confirmation"

        ConfirmationReader.new(message: message).confirmation
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
        @normalized_message ||= message.downcase.gsub(/[^\p{Alnum}']+/, " ").squish
      end

      def multilingual_attempt_cancellation?
        normalized_message.match?(/\b(?:batalkan|hentikan)\b.*\b(?:percubaan|sebut harga)\b/) ||
          normalized_message.match?(/取消.*(?:尝试|報價|报价)/)
      end

      def existing_booking_wording?
        normalized_message.match?(/\b(?:my|existing|current|upcoming)\s+(?:booking|reservation|stay)\b/) ||
          normalized_message.match?(/\bi have (?:a )?(?:booking|reservation)\b/) ||
          normalized_message.match?(/\btempahan saya\b/) || normalized_message.match?(/我的.*(?:预订|預訂)/)
      end
      end
    end
  end
end

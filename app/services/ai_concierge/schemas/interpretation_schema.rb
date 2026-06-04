module AiConcierge
  module Schemas
    class InterpretationSchema
      MESSAGE_TYPES = AiConcierge::Agents::InterpreterAgent::MESSAGE_TYPES
      REQUIRED_SIGNAL_KEYS = %w[is_reset is_resume is_correction starts_new_booking_branch end_conversation].freeze

      def valid?(interpretation)
        interpretation.is_a?(Hash) &&
          MESSAGE_TYPES.include?(interpretation["message_type"]) &&
          interpretation["intent"].present? &&
          interpretation["topic"].present? &&
          interpretation["slots"].is_a?(Hash) &&
          valid_signals?(interpretation["conversation_signals"])
      end

      private

      def valid_signals?(signals)
        signals.is_a?(Hash) && REQUIRED_SIGNAL_KEYS.all? { |key| signals.key?(key) }
      end
    end
  end
end

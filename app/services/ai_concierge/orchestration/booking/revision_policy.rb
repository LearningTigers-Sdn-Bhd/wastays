module AiConcierge
  module Orchestration
    module Booking
      class RevisionPolicy
      REVISION_SLOT_KEYS = %w[
        target_month target_year month_segment check_in check_out nights days
        party_size_total adults children room_count
      ].freeze

      def initialize(message:, interpretation:, active_branch:, pending_question:)
        @message = message.to_s
        @interpretation = interpretation.is_a?(Hash) ? interpretation : {}
        @active_branch = active_branch.is_a?(Hash) ? active_branch : {}
        @pending_question = pending_question
      end

      def call
        return unless booking_ready_for_revision?
        return if blocked_by_interpretation?
        return if timing_or_party_revision?

        return :change_option if option_revision_message?
        return if pending_question == "rate_plan_selection"
        return :change_rate if rate_revision_message?

        nil
      end

      private

      attr_reader :message, :interpretation, :active_branch, :pending_question

      def booking_ready_for_revision?
        Array(active_branch["suggested_options"]).present? &&
          branch_has_timing? &&
          !branch_duration_missing? &&
          !branch_guest_count_missing? &&
          !branch_party_split_missing?
      end

      def blocked_by_interpretation?
        informational_intent?(interpretation["intent"]) ||
          interpretation.dig("conversation_signals", "end_conversation") ||
          interpretation["intent"] == "confirmation"
      end

      def timing_or_party_revision?
        REVISION_SLOT_KEYS.any? do |key|
          value = interpretation.dig("slots", key)
          value.present? && value != 0
        end
      end

      def rate_revision_message?
        return false unless selected_booking_option_present?

        normalized_message.match?(/\b(?:change|switch|choose|select|show|see|different|another|other|new)\b.*\b(?:rate|rates|rate plan|plan|plans)\b/) ||
          normalized_message.match?(/\b(?:rate|rates|rate plan|plan|plans)\b.*\b(?:change|switch|choose|select|show|see|different|another|other|new)\b/) ||
          normalized_message.match?(/\b(?:refundable|non refundable|nonrefundable|standard|flexible|cheaper|cheapest|lowest)\b.*\b(?:instead|please|rate|plan)\b/)
      end

      def option_revision_message?
        normalized_message.match?(/\b(?:change|switch|choose|select|pick|show|see|different|another|other|new)\b.*\b(?:room|rooms|option|options|choice|choices|suite|villa)\b/) ||
          normalized_message.match?(/\b(?:room|rooms|option|options|choice|choices|suite|villa)\b.*\b(?:change|switch|choose|select|pick|show|see|different|another|other|new)\b/)
      end

      def selected_booking_option_present?
        (active_branch["selected_option"] || active_branch["confirmation_candidate"]).present?
      end

      def branch_has_timing?
        active_branch["check_in"].present? || active_branch["target_month"].present?
      end

      def branch_duration_missing?
        active_branch["check_out"].blank? &&
          active_branch["nights"].to_i <= 0 &&
          active_branch["days"].to_i <= 0
      end

      def branch_guest_count_missing?
        active_branch["party_size_total"].to_i <= 0 &&
          active_branch["adults"].to_i <= 0 &&
          active_branch["children"].to_i <= 0
      end

      def branch_party_split_missing?
        total = active_branch["party_size_total"].to_i
        return false if total <= 0

        (active_branch["adults"].to_i + active_branch["children"].to_i) != total
      end

      def informational_intent?(intent)
        %w[hotel_policy hotel_information nearby_attractions room_information booking_context].include?(intent.to_s)
      end

      def normalized_message
        @normalized_message ||= message.downcase.gsub(/[^a-z0-9]+/, " ").squish
      end
      end
    end
  end
end

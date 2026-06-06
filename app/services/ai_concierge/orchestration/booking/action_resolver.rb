module AiConcierge
  module Orchestration
    module Booking
      class ActionResolver
        def initialize(interpretation:, active_branch:, pending_question:)
          @interpretation = interpretation
          @active_branch = active_branch || {}
          @pending_question = pending_question
        end

        def call
          if pending_question == "party_split"
            return :search_options unless missing_party_split?
            return :ask_party_split if interpretation["intent"] == "confirmation"
          end

          return :rate_plan_selection if pending_question == "rate_plan_selection"
          return :confirmation_yes if confirmation_yes?
          return :confirmation_no if confirmation_no?
          return :option_selection if interpretation["intent"] == "option_selection"
          return :ask_booking_timing if missing_timing?
          return :ask_specific_timing if missing_specific_timing?
          return :ask_duration if missing_duration?
          return :ask_adult_count if missing_adult_count?
          return :ask_guest_count if missing_guest_count?
          return :ask_party_split if missing_party_split?

          :search_options
        end

        private

        attr_reader :interpretation, :active_branch, :pending_question

        def confirmation_yes?
          return false unless pending_question == "confirm_selection"

          interpretation["intent"] == "confirmation" && interpretation.dig("slots", "confirmation") != "no"
        end

        def confirmation_no?
          return false unless pending_question == "confirm_selection"

          interpretation["intent"] == "confirmation" && interpretation.dig("slots", "confirmation") == "no"
        end

        def missing_timing?
          active_branch["check_in"].blank? && active_branch["target_month"].blank?
        end

        def missing_specific_timing?
          active_branch["target_month"].present? &&
            active_branch["check_in"].blank? &&
            active_branch["month_segment"].blank?
        end

        def missing_duration?
          has_timing? && duration_missing?
        end

        def has_timing?
          active_branch["check_in"].present? || active_branch["target_month"].present?
        end

        def duration_missing?
          active_branch["check_out"].blank? &&
            active_branch["nights"].to_i <= 0 &&
            active_branch["days"].to_i <= 0
        end

        def missing_adult_count?
          active_branch["children"].to_i.positive? && active_branch["adults"].to_i <= 0
        end

        def missing_guest_count?
          active_branch["party_size_total"].to_i <= 0 &&
            active_branch["adults"].to_i <= 0 &&
            active_branch["children"].to_i <= 0
        end

        def missing_party_split?
          total = active_branch["party_size_total"].to_i
          return false if total <= 0

          adults = active_branch["adults"].to_i
          children = active_branch["children"].to_i

          (adults + children) != total
        end
      end
    end
  end
end

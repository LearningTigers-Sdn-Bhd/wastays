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
          return :option_selection if selecting_from_options?
          return :ask_date_range_month if pending_date_range_month?
          return :ask_booking_timing if missing_timing?
          return :ask_specific_timing if missing_specific_timing?
          return :ask_duration if missing_duration?
          return :ask_adult_count if missing_adult_count?
          return :ask_guest_count if missing_guest_count?
          return :ask_party_split if missing_party_split?
          return :ask_confirmation if unreadable_confirmation?

          :search_options
        end

        private

        attr_reader :interpretation, :active_branch, :pending_question

        # A selection needs something to select from.
        #
        # The turn is read as an option selection whenever the thread is
        # waiting on "select_option", which is right while a list is on the
        # table and nonsense once it is gone: every message then matches no
        # option, and the guest is told to pick from a list they were never
        # shown. Without options the question is still open, so this falls
        # through to whichever one the ladder below has not answered yet.
        def selecting_from_options?
          interpretation["intent"] == "option_selection" && Array(active_branch["suggested_options"]).present?
        end

        # An answer to the confirmation that could not be read is still an
        # answer to the confirmation.
        #
        # Everything above this line is a question the ladder has not reached
        # yet, and below it is a fresh search -- which is what a "yes" the model
        # forgot to pass along used to fall through to: the guest was shown the
        # catalogue they had already chosen from, with their choice gone and
        # their quote never made.
        #
        # A turn that really does change the search has already cleared the
        # candidate by the time this runs -- that is what SlotMerger does with
        # a changed date or party -- so the candidate still being here is the
        # evidence that nothing changed. Asking the model's own slots instead
        # reads values the normalizer has already thrown away as unevidenced,
        # which is how "sounds good to me" was heard as a party of one.
        def unreadable_confirmation?
          pending_question == "confirm_selection" && confirmation_target.present?
        end

        def confirmation_target
          active_branch["confirmation_candidate"] || active_branch["selected_option"]
        end

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

        def pending_date_range_month?
          clarification = active_branch["clarification_needed"]
          clarification.is_a?(Hash) &&
            clarification["type"] == "date_range_month" &&
            active_branch["check_in"].blank? &&
            active_branch["target_month"].blank?
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

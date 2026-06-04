module AiConcierge
  module Orchestration
    module Conversation
      class InterpretationPipeline
        PreparedTurn = Struct.new(:conversation_state, :interpretation, :active_branch, :decision, keyword_init: true)

        def initialize(hotel:, message:)
          @hotel = hotel
          @message = message.to_s.strip
        end

        def interpret(conversation_state:)
          interpretation = Agents::InterpreterAgent.new(
            hotel: hotel,
            message: message,
            conversation_summary: State::ConversationSummaryBuilder.new(conversation_state: conversation_state).call
          ).call
          validate_interpretation!(interpretation)
          interpretation
        end

        def prepare(conversation_state:, interpretation:)
          interpretation["conversation_signals"]["end_conversation"] = false
          interpretation = Core::InformationIntentGuard.new(message: message, interpretation: interpretation).call
          booking_context = prepare_booking_context(conversation_state, interpretation)
          conversation_state = booking_context[:conversation_state]
          task_manager = booking_context[:task_manager]
          base_branch = booking_context[:base_branch]
          current_pending_question = booking_context[:pending_question]

          slots = Booking::InputNormalizer.new(
            message: message,
            slots: interpretation["slots"],
            pending_question: current_pending_question,
            conversation_signals: interpretation["conversation_signals"],
            active_branch: base_branch
          ).call

          active_branch = State::SlotMerger.new(
            active_branch: base_branch,
            slots: slots,
            pending_question: current_pending_question,
            message: message
          ).call

          decision = Core::TransitionPolicy.new(
            interpretation: interpretation,
            active_branch: active_branch,
            pending_question: current_pending_question,
            message: message,
            booking_task: task_manager.booking_task
          ).call

          PreparedTurn.new(
            conversation_state: conversation_state,
            interpretation: interpretation,
            active_branch: active_branch,
            decision: decision
          )
        end

        private

        attr_reader :hotel, :message

        def validate_interpretation!(interpretation)
          return if Schemas::InterpretationSchema.new.valid?(interpretation)

          raise ArgumentError, "invalid interpretation payload"
        end

        def prepare_booking_context(conversation_state, interpretation)
          task_manager = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload)

          if task_manager.booking_pending_question.blank? && conversation_state.pending_question.present?
            normalized_payload = task_manager.activate_booking(task_manager.booking_branch, pending_question: conversation_state.pending_question)
            conversation_state = temporary_state(conversation_state, normalized_payload)
            task_manager = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload)
          end

          pending_question = task_manager.booking_pending_question || conversation_state.pending_question
          base_branch = task_manager.booking_branch

          if interpretation.dig("conversation_signals", "starts_new_booking_branch")
            conversation_state = temporary_state(conversation_state, task_manager.archive_completed_booking)
            task_manager = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload)
            pending_question = nil
            base_branch = empty_branch
          elsif fresh_booking_request_without_details?(interpretation, pending_question)
            conversation_state = temporary_state(conversation_state, task_manager.reset_booking_task)
            task_manager = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload)
            pending_question = nil
            base_branch = empty_branch
          end

          {
            conversation_state: conversation_state,
            task_manager: task_manager,
            base_branch: base_branch,
            pending_question: pending_question
          }
        end

        def temporary_state(conversation_state, slots_payload)
          conversation_state.tap do |state|
            state.assign_attributes(slots_payload: slots_payload)
          end
        end

        def fresh_booking_request_without_details?(interpretation, pending_question)
          return false unless %w[booking_timing specific_timing].include?(pending_question.to_s)
          return false unless interpretation["intent"] == "booking_search"
          return false if booking_detail_slots_present?(interpretation["slots"])

          normalized = message.downcase.gsub(/[^a-z0-9]+/, " ").squish
          normalized.match?(/\b(?:book|booking|reserve|reservation|make booking|new booking|start booking)\b/) &&
            !normalized.match?(/\b(?:this month|next month|today|tomorrow|tonight|early|mid|late|jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december|\d)\b/)
        end

        def booking_detail_slots_present?(slots)
          %w[target_month target_year month_segment check_in check_out nights days party_size_total adults children room_count option_number].any? do |key|
            value = slots&.dig(key)
            value.present? && value != 0
          end
        end

        def empty_branch
          State::SlotMerger.empty_branch
        end
      end
    end
  end
end

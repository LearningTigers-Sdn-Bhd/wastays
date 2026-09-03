# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module Booking
      # Gets a booking turn ready: normalise what was said, merge it into the
      # branch already in Postgres, and settle which question is open.
      #
      # Lifted out of InterpretationPipeline so the tool-calling loop and the
      # pipeline it replaces run the identical code. Two spellings of "merge
      # these slots into that booking" is exactly how a rewrite loses a guest's
      # dates.
      class PrepareTurn
        Prepared = Struct.new(:conversation_state, :active_branch, :pending_question, keyword_init: true)

        def initialize(conversation_state:, interpretation:, message:)
          @conversation_state = conversation_state
          @interpretation = interpretation
          @message = message.to_s
        end

        def call
          state = conversation_state
          manager = State::ConversationTaskManager.new(slots_payload: state.slots_payload)
          state = with_payload(state, manager.reset_information_run)
          manager = State::ConversationTaskManager.new(slots_payload: state.slots_payload)

          if manager.booking_pending_question.blank? && state.pending_question.present?
            state = with_payload(state, manager.activate_booking(manager.booking_branch, pending_question: state.pending_question))
            manager = State::ConversationTaskManager.new(slots_payload: state.slots_payload)
          end

          pending_question = manager.booking_pending_question || state.pending_question
          base_branch = manager.booking_branch

          if interpretation.dig("conversation_signals", "starts_new_booking_branch")
            state = with_payload(state, manager.archive_completed_booking)
            pending_question = nil
            base_branch = State::SlotMerger.empty_branch
          end

          slots = InputNormalizer.new(
            message: message,
            slots: interpretation["slots"],
            pending_question: pending_question,
            conversation_signals: interpretation["conversation_signals"],
            evidence: interpretation["evidence"],
            active_branch: base_branch
          ).call

          Prepared.new(
            conversation_state: state,
            active_branch: State::SlotMerger.new(
              active_branch: base_branch,
              slots: slots,
              pending_question: pending_question,
              message: message
            ).call,
            pending_question: pending_question
          )
        end

        private

        attr_reader :conversation_state, :interpretation, :message

        def with_payload(state, slots_payload)
          state.tap { |record| record.assign_attributes(slots_payload: slots_payload) }
        end
      end
    end
  end
end

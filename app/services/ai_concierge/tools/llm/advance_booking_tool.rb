# frozen_string_literal: true

module AiConcierge
  module Tools
    module Llm
      # The one door between the model and money.
      #
      # What the model contributes is slot extraction: what this message says.
      # It does not choose the next question, does not decide whether the guest
      # confirmed, and cannot reach quote generation -- generate_booking_url is
      # not a tool it has. Booking::ActionResolver still owns the order of the
      # questions, because that order is a product decision, and
      # `pending_question` still owns what a "yes" means, because that lock
      # lives in Postgres.
      class AdvanceBookingTool < BaseTool
        ALREADY_ADVANCED = { advanced: false, reason: "already advanced this turn" }.freeze

        description <<~DESCRIPTION
          Advance the guest's booking. Use this whenever they are trying to
          book, reserve, check availability, price a stay, ask what a room
          costs, pick from options you have shown them, choose a rate plan, or
          answer a question the hotel asked them about their booking.

          Extract only what this message actually states. Never invent or carry
          over dates, party size or duration -- anything you do not pass is
          remembered from earlier turns. Do not decide what to ask next and do
          not write the reply: the booking system owns both. Call this at most
          once per turn.
        DESCRIPTION

        params do
          object :slots, description: "Only what this message states. Omit anything it does not." do
            integer :target_month, description: "1-12, when the guest names a month without a date"
            integer :target_year
            string :month_segment, enum: %w[early mid late]
            integer :nights
            integer :days
            integer :party_size_total, description: "A total the guest has not split into adults and children"
            integer :adults
            integer :children
            integer :room_count
            string :option_number, description: "Which of the shown options they picked"
            string :confirmation, enum: %w[yes no], description: "Only when answering a yes/no the hotel asked"
            string :check_in, description: "ISO 8601 date"
            string :check_out, description: "ISO 8601 date"
            string :room_type_name
            string :rate_plan_name
          end
          object :signals do
            boolean :is_reset, description: "They want to start over"
            boolean :is_correction, description: "They are correcting something they said before"
            boolean :starts_new_booking_branch, description: "They want a second, separate booking"
          end
        end

        def execute(slots: {}, signals: {})
          return ALREADY_ADVANCED if recorder.booking_advanced?

          recorder.mark_booking_advanced!

          interpretation = SyntheticInterpretation.new(
            slots: slots, signals: signals, pending_question: context.pending_question
          ).call
          prepared = Orchestration::Booking::PrepareTurn.new(
            conversation_state: context.conversation_state,
            interpretation: interpretation,
            message: context.message
          ).call

          domain_result = Orchestration::Booking::Orchestrator.new(
            hotel: hotel,
            prospect: context.prospect,
            conversation_state: prepared.conversation_state,
            interpretation: interpretation,
            active_branch: prepared.active_branch,
            decision: { action: decision_action, pending_question: prepared.pending_question },
            message: context.message,
            phone: context.phone
          ).call

          record(domain_result, digest: { advanced: true })
          halt("The booking system has answered the guest. Stop.")
        end

        private

        # A booking put down to answer a question is picked up again, and that
        # is decided from the thread rather than from the model: whether one is
        # suspended is a fact, and the model has already said the useful part
        # by choosing this tool at all.
        def decision_action = context.resumable_booking? ? :resume : :booking

        # Intent is derived from the open question, never from the model.
        # "Yes" means a confirmation only while a confirmation is what was
        # asked; at any other moment it is just a word.
        class SyntheticInterpretation
          DEFAULT_SIGNALS = {
            "is_reset" => false, "is_resume" => false, "is_correction" => false,
            "starts_new_booking_branch" => false, "end_conversation" => false
          }.freeze

          def initialize(slots:, signals:, pending_question:)
            @slots = (slots || {}).deep_stringify_keys.compact
            @signals = (signals || {}).deep_stringify_keys.compact
            @pending_question = pending_question
          end

          def call
            {
              "message_type" => "booking_request",
              "intent" => intent,
              "topic" => "booking_search",
              "confidence" => 1.0,
              "slots" => slots,
              "tool_hints" => [],
              "conversation_signals" => DEFAULT_SIGNALS.merge(signals)
            }
          end

          private

          attr_reader :slots, :signals, :pending_question

          def intent
            return "confirmation" if pending_question == "confirm_selection" && slots["confirmation"].present?
            return "option_selection" if slots["option_number"].present?

            # Options are on the table, so whatever the guest just said is an
            # answer to them -- a date, a room name, an ordinal. Reading that as
            # a fresh search would show the same list again and strand them.
            return "option_selection" if pending_question == "select_option"

            "booking_search"
          end
        end
      end
    end
  end
end

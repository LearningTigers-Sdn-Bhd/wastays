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
      class AdvanceBookingFunction < BaseFunction
        ALREADY_ADVANCED = { advanced: false, reason: "already advanced this turn" }.freeze

        description <<~DESCRIPTION
          Advance the guest's booking. Use this whenever they are trying to
          book, reserve, check availability, price a stay, ask what a room
          costs, pick from options you have shown them, choose a rate plan, or
          answer a question the hotel asked them about their booking.

          Use it even when the message states nothing to extract -- "can I make
          a booking" is a booking turn, and the booking system will ask the
          first question itself.

          Extract only what this message actually states. Never invent or carry
          over dates, party size or duration -- anything you do not pass is
          remembered from earlier turns. Today's date is context for reading
          what the guest wrote, never a value to fall back on: a message that
          names no month has no month, and passing this month because it is the
          one you know puts a date in front of the guest that they never chose.
          Do not decide what to ask next and do not write the reply: the booking
          system owns both. Call this at most once per turn.
        DESCRIPTION

        params do
          object :slots, description: "Only what this message states. Omit anything it does not." do
            integer :target_month, description: "1-12, only when the guest names a month without a date. Never today's month by default."
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
            string :check_in, description: "ISO 8601 date, only when the guest states one. Never today's date by default."
            string :check_out, description: "ISO 8601 date"
            string :room_type_name
            string :option_action, enum: %w[details continue], description: "Whether the guest asks to view an option or continue booking it"
          end
          object :evidence, description: "Quote the guest's own words, copied exactly from their message, for each thing you filled in. Whatever language they wrote in. Leave a field out when the message does not say it." do
            string :timing, description: "The words that say when they arrive"
            string :checkout, description: "The words that say when they leave"
            string :duration, description: "The words that say how long they stay"
            string :party, description: "The words that say how many people"
          end
          object :signals do
            boolean :is_reset, description: "They want to start over"
            boolean :is_correction, description: "They are correcting something they said before"
            boolean :starts_new_booking_branch, description: "They want a second, separate booking"
          end
        end

        def execute(slots: {}, signals: {}, evidence: {})
          return ALREADY_ADVANCED if recorder.booking_advanced?

          recorder.mark_booking_advanced!

          interpretation = SyntheticInterpretation.new(
            slots: slots, signals: signals, evidence: evidence,
            pending_question: context.pending_question, message: context.message,
            resumed: context.resumable_booking?
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
            decision: { action: decision_action, pending_question: prepared.pending_question, purpose: booking_purpose },
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

        def booking_purpose
          current = context.task_manager.booking_purpose
          return "price_exploration" if accepted_price_offer?
          return purpose_after_price_exploration if current == "price_exploration"
          return "booking" if booking_intent.booking_commitment?
          return "price_exploration" if booking_intent.rate_question?

          current
        end

        def purpose_after_price_exploration
          return "price_exploration" unless booking_intent.explicit_purchase_commitment?
          return "booking" if option_chosen?
          return "booking" unless priced_options_available?

          "price_exploration"
        end

        def accepted_price_offer?
          context.pending_price_offer? && confirmation == "yes"
        end

        def option_chosen?
          context.booking_branch["viewed_option"].present? ||
            Matching::OptionReference.new(message: context.message).number.present?
        end

        def priced_options_available?
          Array(context.booking_branch["suggested_options"]).any?
        end

        def confirmation
          @confirmation ||= Orchestration::Core::ConfirmationReader.new(message: context.message).confirmation
        end

        def booking_intent
          @booking_intent ||= Matching::BookingIntentMatcher.new(message: context.message)
        end

        # Intent is derived from the open question, never from the model.
        # "Yes" means a confirmation only while a confirmation is what was
        # asked; at any other moment it is just a word.
        class SyntheticInterpretation
          DEFAULT_SIGNALS = {
            "is_reset" => false, "is_resume" => false, "is_correction" => false,
            "starts_new_booking_branch" => false, "end_conversation" => false
          }.freeze

          def initialize(slots:, signals:, pending_question:, evidence: {}, message: nil, resumed: false)
            @slots = (slots || {}).deep_stringify_keys.compact
            @signals = (signals || {}).deep_stringify_keys.compact
            @evidence = (evidence || {}).deep_stringify_keys.compact
            @pending_question = pending_question
            @message = message.to_s
            @resumed = resumed
          end

          def call
            {
              "message_type" => "booking_request",
              "intent" => intent,
              "topic" => "booking_search",
              "confidence" => 1.0,
              "slots" => slots,
              "evidence" => evidence,
              "tool_hints" => [],
              "conversation_signals" => DEFAULT_SIGNALS.merge(signals)
            }
          end

          private

          attr_reader :signals, :evidence, :pending_question, :message, :resumed

          # The model is asked for a `confirmation` and does not always send
          # one: a bare "yes" comes back as a booking turn with nothing in it,
          # and the guest who had just chosen a room is shown the catalogue
          # again with their choice gone.
          #
          # Read here rather than trusted from the model, and only while a
          # yes/no is the open question -- the same lock the intent below has
          # always used. Both questions that ask one are covered: the
          # confirmation, and the party split, whose own reply tells the guest
          # in as many words to answer *Yes*.
          def slots
            return @slots if @slots["confirmation"].present?
            return @slots if spoken_confirmation.blank?

            @slots.merge("confirmation" => spoken_confirmation)
          end

          YES_NO_QUESTIONS = %w[confirm_selection party_split price_option_continuation].freeze

          # The same words the control handler reads a goodbye by, asked of the
          # same message. One vocabulary, so a yes the hotel accepts in one
          # place is a yes in the other.
          def spoken_confirmation
            return unless YES_NO_QUESTIONS.include?(pending_question)

            @spoken_confirmation ||= Orchestration::Core::ConfirmationReader.new(message: message).confirmation
          end

          def intent
            return "confirmation" if pending_question == "confirm_selection" && slots["confirmation"].present?

            return "option_selection" if slots["option_number"].present?

            # A booking picked up after an interruption is picked up in mid-air.
            # Nothing has told the model a list is waiting -- the thread was
            # suspended, and whatever question was open on it went quiet -- so
            # "2" arrives as an ordinary sentence. A message that is a row and
            # nothing else can be about nothing else, whichever question the
            # booking was put down on.
            return "option_selection" if resumed && Matching::OptionReference.new(message: message).only_reference?

            # Options are on the table, so whatever the guest just said is an
            # answer to them -- a row, an ordinal, a date. Reading that as a
            # fresh search would show the same list again and strand them.
            return "option_selection" if %w[select_option price_option_exploration].include?(pending_question)

            "booking_search"
          end
        end
      end
    end
  end
end

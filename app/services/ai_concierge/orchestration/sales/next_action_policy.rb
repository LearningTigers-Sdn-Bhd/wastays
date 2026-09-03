# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module Sales
      # Selects the next commercial action from application-owned facts.
      class NextActionPolicy
        INFORMATION_INTENTS = %w[hotel_information hotel_policy nearby_attractions].freeze
        OPTIONAL_ACTIONS = NextAction::OPTIONAL_KINDS

        def initialize(intent:, outcome:, booking_task:, resumable_booking:, topic: nil, needs_human_support: false, suppress_offer: false)
          @intent = intent.to_s
          @topic = topic.to_s
          @outcome = outcome.to_s
          @booking_task = booking_task.is_a?(Hash) ? booking_task : {}
          @resumable_booking = resumable_booking
          @needs_human_support = needs_human_support
          @suppress_offer = suppress_offer
        end

        def call
          kind = selected_kind
          kind = "none" if suppress_offer && OPTIONAL_ACTIONS.include?(kind)
          NextAction.new(kind)
        end

        private

        attr_reader :intent, :topic, :outcome, :booking_task, :resumable_booking, :needs_human_support, :suppress_offer

        def selected_kind
          return "offer_front_desk" if needs_human_support
          return "none" if outcome == "clarification"
          return "resume_booking" if outcome == "answered" && resumable_booking
          return "offer_alternative_search" if outcome == "no_options"
          return "continue_booking" if active_booking_question?
          return "offer_front_desk" if outcome == "unavailable"
          return "offer_price_search" if outcome == "answered" && intent == "room_information"
          return "offer_guided_hotel_exploration" if outcome == "answered" && topic == "hotel_overview"
          return "offer_booking_help" if outcome == "answered" && INFORMATION_INTENTS.include?(intent)

          "none"
        end

        def active_booking_question?
          booking_task["pending_question"].present? && !booking_task["status"].in?(%w[suspended expired])
        end
      end
    end
  end
end

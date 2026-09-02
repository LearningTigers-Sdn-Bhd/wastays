# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module Sales
      # Adds one application-selected action after a hotel-information answer.
      class NextActionRenderer
        REFUSAL_ACKNOWLEDGMENT = "No problem."

        BOOKING_HELP_MESSAGES = [
          "If that suits your plans, I can help you compare rooms for your dates. Is there anything else you’d like to know?",
          "Would you like to see which rooms are available for your dates, or is there anything else I can help with?",
          "I can also help you compare rooms and current prices. What else would you like to know?"
        ].freeze
        NEUTRAL_CLOSERS = [
          "Is there anything else you’d like to know?",
          "What else can I help you with?",
          "Feel free to ask if you’d like to know anything else about the hotel."
        ].freeze

        def initialize(answer:, next_action:, intent:, missing_topic: nil, acknowledge_refusal: false, copy_index: 0,
          closing_copy_index: 0, natural_closer: false)
          @answer = answer.to_s.strip
          @next_action = next_action
          @intent = intent.to_s
          @missing_topic = missing_topic.to_s
          @acknowledge_refusal = acknowledge_refusal
          @copy_index = copy_index.to_i
          @closing_copy_index = closing_copy_index.to_i
          @natural_closer = natural_closer
        end

        def call
          body = acknowledge_refusal ? "#{REFUSAL_ACKNOWLEDGMENT} #{answer}" : answer
          action = action_message
          action.present? ? "#{body}\n\n#{action}" : body
        end

        private

        attr_reader :answer, :next_action, :intent, :missing_topic, :acknowledge_refusal, :copy_index,
          :closing_copy_index, :natural_closer

        def action_message
          case next_action.kind
          when "offer_booking_help" then booking_help_message
          when "offer_price_search" then "Would you like me to check prices for this room for your travel dates?"
          when "offer_guided_hotel_exploration" then "What matters most for your stay: facilities, location, or room choices?"
          when "resume_booking", "continue_booking" then "Would you like to continue your booking?"
          when "offer_alternative_search" then "Would you like me to search another date or room?"
          when "offer_front_desk" then front_desk_message
          when "none" then neutral_closer
          end
        end

        def booking_help_message
          BOOKING_HELP_MESSAGES[closing_copy_index % BOOKING_HELP_MESSAGES.length]
        end

        def neutral_closer
          NEUTRAL_CLOSERS[closing_copy_index % NEUTRAL_CLOSERS.length] if natural_closer
        end

        def front_desk_message
          case missing_topic
          when "nearby attractions"
            "Please ask the front desk for local recommendations."
          when "service information", "an FAQ answer", "policy information"
            "Please ask the front desk for the current details."
          else
            "Please ask the front desk for assistance."
          end
        end
      end
    end
  end
end

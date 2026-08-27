# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module Sales
      # Adds one application-selected action after a hotel-information answer.
      class NextActionRenderer
        REFUSAL_ACKNOWLEDGMENT = "No problem."

        def initialize(answer:, next_action:, intent:, missing_topic: nil, acknowledge_refusal: false)
          @answer = answer.to_s.strip
          @next_action = next_action
          @intent = intent.to_s
          @missing_topic = missing_topic.to_s
          @acknowledge_refusal = acknowledge_refusal
        end

        def call
          body = acknowledge_refusal ? "#{REFUSAL_ACKNOWLEDGMENT} #{answer}" : answer
          action = action_message
          action.present? ? "#{body}\n\n#{action}" : body
        end

        private

        attr_reader :answer, :next_action, :intent, :missing_topic, :acknowledge_refusal

        def action_message
          case next_action.kind
          when "offer_booking_help" then booking_help_message
          when "offer_price_search" then "Would you like me to check prices for this room for your travel dates?"
          when "resume_booking", "continue_booking" then "Would you like to continue your booking?"
          when "offer_alternative_search" then "Would you like me to search another date or room?"
          when "offer_front_desk" then front_desk_message
          when "none" then nil
          end
        end

        def booking_help_message
          return "If this policy works for you, I can help you find a room for your travel dates." if intent == "hotel_policy"

          "Would you like me to help you find a room for your travel dates?"
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

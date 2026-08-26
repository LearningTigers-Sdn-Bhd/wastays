# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module HotelKnowledge
      # Resolves short answers to questions asked by the knowledge composer.
      # Conversation history helps the model, but it is not state. This reader
      # makes "facility", "the third one" and room choices deterministic.
      class ClarificationResolver
        ORDINALS = {
          "first" => 0, "1" => 0, "one" => 0,
          "second" => 1, "2" => 1, "two" => 1,
          "third" => 2, "3" => 2, "three" => 2,
          "fourth" => 3, "4" => 3, "four" => 3
        }.freeze

        GENERIC_FACILITY = /\A(?:a |the )?(?:facility|facilities|amenity|amenities)\z/i
        CHECK_IN = /\b(?:check[ -]?in|hotel|arrival)\b/i
        FACILITY = /\b(?:bar|breakfast|cafe|fitness|gym|parking|pool|reception|restaurant|shuttle|spa|front desk)\b/i
        GENERIC_CHOICE = /\A(?:that|this|it|that one|this one|one of them|the policy|policy)\z/i

        def initialize(context:)
          @context = context
        end

        def call
          case pending_question
          when "opening_hours_subject" then resolve_opening_hours_subject
          when "facility_opening_hours" then resolve_facility_name
          when "policy_topic" then resolve_policy_topic
          when "room_type_choice" then resolve_room_type_choice
          when "room_type_name" then resolve_room_type_name
          end
        end

        private

        attr_reader :context

        def pending_question = information_task["pending_question"].presence
        def information_task = context.task_manager.information_task
        def clarification_context = information_task["context"].is_a?(Hash) ? information_task["context"] : {}
        def message = context.message.strip

        def resolve_opening_hours_subject
          return answer_policy("What is the hotel check-in time?", fact: "check_in_time") if message.match?(CHECK_IN)
          return ask_for_facility if message.match?(GENERIC_FACILITY)
          return unless facility_reference?

          answer_information("What are the opening hours for #{message}?")
        end

        def resolve_facility_name
          return ask_for_facility if message.match?(GENERIC_FACILITY) || message.blank?
          return unless facility_reference?

          answer_information("What are the opening hours for #{message}?")
        end

        def resolve_policy_topic
          choice = selected_choice(Array(clarification_context["choices"])) || policy_choice_from_message
          if choice.blank?
            return ask_again("Which policy would you like to know about: check-in, check-out, cancellation, or house rules?", "policy_topic") if message.match?(GENERIC_CHOICE)

            return
          end

          fact = {
            "check-in" => "check_in_time",
            "check-out" => "check_out_time",
            "cancellation" => "cancellation_policy"
          }[choice]
          answer_policy("What is the #{choice} policy?", fact: fact)
        end

        def resolve_room_type_choice
          choices = Array(clarification_context["choices"])
          choice = selected_choice(choices) || choices.find { |name| message.downcase.include?(name.downcase) }
          if choice.blank?
            return ask_again("I found several matching room types: #{choices.to_sentence}. Which one do you mean?", "room_type_choice", choices:) if message.match?(GENERIC_CHOICE)

            return
          end

          answer_room(choice)
        end

        def resolve_room_type_name
          return ask_again("Please send the room type name.", "room_type_name") if message.blank?
          return unless room_type_reference?

          answer_room(message)
        end

        def facility_reference?
          return true if message.match?(FACILITY)

          amenity_names = Hotel::HOTEL_AMENITIES.filter_map do |amenity|
            amenity[:name] if Array(context.hotel.amenities).include?(amenity[:id])
          end
          amenity_names.any? { |name| message.downcase.include?(name.downcase) }
        end

        def room_type_reference?
          result = Matching::RoomTypeMatcher.new(
            room_types: context.hotel.room_types,
            query: message,
            hinted_room_type_name: message
          ).call
          result["success"] || result["error"] == "ambiguous_room_type"
        end

        def selected_choice(choices)
          normalized = message.downcase
          word = ORDINALS.keys
            .select { |candidate| normalized.match?(/\b#{Regexp.escape(candidate)}\b/) }
            .min_by { |candidate| normalized.index(candidate) }
          index = ORDINALS[word]
          choices[index] if index
        end

        def policy_choice_from_message
          normalized = message.downcase
          return "check-in" if normalized.match?(/\bcheck[ -]?in\b/)
          return "check-out" if normalized.match?(/\bcheck[ -]?out\b/)
          return "cancellation" if normalized.match?(/\bcancel/)
          "house rules" if normalized.match?(/\b(?:house|rules?|restriction)\b/)
        end

        def ask_for_facility
          ask_again(
            "Which facility do you mean, such as the pool, spa, fitness centre, or restaurant?",
            "facility_opening_hours"
          )
        end

        def ask_again(answer, next_question, choices: nil)
          payload = State::ConversationTaskManager.new(slots_payload: context.conversation_state.slots_payload)
            .update_information_task(
              intent: "hotel_information",
              topic: "general_hotel_info",
              question: message,
              pending_question: next_question,
              context: choices.present? ? { "choices" => choices } : nil
            )

          Core::DomainResponse.new(
            slots_payload: payload,
            reply_type: :general_hotel_info,
            extra_context: {
              result: { "answer" => answer, "shape" => "clarification", "answer_mode" => "deterministic", "success" => false },
              knowledge_reply: true
            }
          )
        end

        def answer_policy(query, fact: nil)
          answer(query:, intent: "hotel_policy", topic: "hotel_policy", fact: fact)
        end

        def answer_information(query)
          answer(query:, intent: "hotel_information", topic: "general_hotel_info")
        end

        def answer_room(room_type_name)
          answer(
            query: "Tell me about #{room_type_name}",
            intent: "room_information",
            topic: "room_information",
            slots: { "room_type_name" => room_type_name }
          )
        end

        def answer(query:, intent:, topic:, fact: nil, slots: {})
          Orchestrator.new(
            hotel: context.hotel,
            message: query,
            interpretation: {
              "intent" => intent,
              "topic" => topic,
              "scope" => "specific",
              "slots" => slots,
              "retrieval_hints" => Retrieval::QueryHints.new(fact: fact, preferred_language: context.thread_language).to_h
            },
            conversation_state: context.conversation_state,
            pause: context.info_interruption_active?,
            active_branch: context.booking_branch,
            language: context.thread_language
          ).call
        end
      end
    end
  end
end

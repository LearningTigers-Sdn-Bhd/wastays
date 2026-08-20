# frozen_string_literal: true

module AiConcierge
  module Tools
    module Llm
      # Collapses three tools into one.
      #
      # get_hotel_policy, get_general_hotel_info and get_hotel_faq differed only
      # by which shelf the answer was on -- a distinction the guest cannot make
      # and the model kept getting wrong, which is most of why
      # InformationIntentGuard had to exist. Here the shelf is a hint, and
      # HybridAnswerBuilder already searches the other shelves when the hint
      # turns out to be wrong.
      class AnswerHotelQuestionTool < BaseTool
        CATEGORIES = %w[policy general_info faq].freeze

        description <<~DESCRIPTION
          Answer a question about the hotel itself, from what the hotel has
          published: policies (check-in, check-out, cancellation, house rules,
          what to know before booking), facilities, amenities, services
          (parking, transport, wifi, breakfast, restaurant, spa, pool, room
          service), and frequently asked questions.

          Use this when the guest wants to know something. Do not use it to
          price a stay or check whether a room is free on given dates -- a
          question about what a room costs is an attempt to book, because the
          answer depends on dates, and belongs to advance_booking.
        DESCRIPTION

        param :question, type: "string",
          desc: "The guest's question, word for word. Do not rephrase, translate or summarise it."
        param :category, type: "string", required: false,
          desc: "Where the answer is most likely to live: policy, general_info or faq. " \
                "A wrong guess is recovered automatically, so omit it rather than forcing one."
        param :search_terms, type: "string", required: false,
          desc: "A few words to look this question up by, space separated. " \
                "Give them in every language the hotel's documents are written in, " \
                "not only the guest's -- the search matches words, so a question in " \
                "one language finds nothing in a document written in another."
        param :fact, type: "string", required: false,
          desc: "Set to check_in_time, check_out_time or cancellation_policy when the " \
                "guest is asking exactly that. The hotel answers those from its own " \
                "records, so naming one is faster and cannot be wrong."

        def execute(question:, category: nil, search_terms: nil, fact: nil)
          return advance_booking_instead if rate_question?

          intent = intent_for(category)

          domain_result = Orchestration::HotelKnowledge::Orchestrator.new(
            hotel: hotel,
            message: question.to_s,
            interpretation: {
              "intent" => intent,
              "topic" => topic_for(category),
              "retrieval_hints" => hints_for(search_terms, fact).to_h
            },
            conversation_state: context.conversation_state,
            pause: context.info_interruption_active?,
            active_branch: context.booking_branch
          ).call

          record(domain_result, digest: digest_for(domain_result))
        end

        private

        # The guest's own language is a fact about the thread, so it is read
        # from there rather than asked of the model.
        def hints_for(search_terms, fact)
          Retrieval::QueryHints.new(
            terms: search_terms,
            fact: fact,
            preferred_language: context.thread_language
          )
        end

        def intent_for(category) = category.to_s == "policy" ? "hotel_policy" : "hotel_information"

        def topic_for(category)
          case category.to_s
          when "policy" then "hotel_policy"
          when "faq" then "hotel_faq"
          else "general_hotel_info"
          end
        end

        # Ten tokens, so the model can tell whether the guest has been served
        # without ever seeing what they were told.
        def digest_for(domain_result)
          result = domain_result.dig(:extra_context, :result) || {}
          { answered: result["success"] != false, answer_mode: result["answer_mode"] }
        end
      end
    end
  end
end

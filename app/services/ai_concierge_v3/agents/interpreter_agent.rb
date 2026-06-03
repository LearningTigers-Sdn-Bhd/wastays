require "ruby_llm"
require "ruby_llm/schema"
require "json"

module AiConciergeV3
  module Agents
    class InterpreterAgent
    MESSAGE_TYPES = %w[
      booking_request
      booking_selection
      booking_confirmation
      hotel_info_question
      hotel_policy_question
      room_info_question
      existing_booking_question
      conversation_control
      greeting_or_unknown
    ].freeze

    class InterpretationSchema < RubyLLM::Schema
      string :message_type, enum: MESSAGE_TYPES
      string :intent, enum: [ "booking_search", "option_selection", "confirmation", "booking_context", "hotel_policy", "hotel_information", "nearby_attractions", "room_information", "greeting", "resume", "new_branch", "reset" ]
      string :topic, enum: [ "booking_search", "booking_context", "hotel_policy", "general_hotel_info", "hotel_faq", "nearby_attractions", "room_information", "general" ]
      number :confidence
      object :slots do
        integer :target_month
        integer :target_year
        string :month_segment, enum: [ "early", "mid", "late" ]
        integer :nights
        integer :days
        integer :party_size_total
        integer :adults
        integer :children
        integer :room_count
        string :option_number
        string :confirmation, enum: [ "yes", "no" ]
        string :check_in
        string :check_out
        string :room_type_name
        string :rate_plan_name
      end
      array :tool_hints do
        string enum: [ "search_booking_options", "select_booking_option", "generate_booking_url", "get_hotel_policy", "get_booking_context", "get_general_hotel_info", "get_hotel_faq", "get_nearby_attractions", "get_room_type_details" ]
      end
      object :conversation_signals do
        boolean :is_reset
        boolean :is_resume
        boolean :is_correction
        boolean :starts_new_booking_branch
        boolean :end_conversation
      end
    end

    def initialize(hotel:, message:, conversation_summary:, today: Date.current)
      @hotel = hotel
      @message = message.to_s.strip
      @conversation_summary = conversation_summary || {}
      @today = today
    end

    LLM_TIMEOUT = 30

    def call
      context = RubyLLM.context do |config|
        case hotel.ai_provider_name
        when "openai"
          config.openai_api_key = hotel.ai_concierge_api_key
        when "claude"
          config.anthropic_api_key = hotel.ai_concierge_api_key
        when "gemini"
          config.gemini_api_key = hotel.ai_concierge_api_key
        when "deepseek"
          config.deepseek_api_key = hotel.ai_concierge_api_key
        end
      end

      chat = context.chat(
        model: hotel.ai_concierge_model_name,
        provider: hotel.ai_concierge_provider
      )

      response = Timeout.timeout(LLM_TIMEOUT) do
        if hotel.ai_concierge_structured_output_supported?
          chat.with_schema(InterpretationSchema).ask(prompt)
        else
          chat.ask(prompt)
        end
      end
      content = response&.content || raise("Empty response from LLM")

      if hotel.ai_concierge_structured_output_supported?
        content
      else
        parse_fallback_response(content)
      end
    rescue Timeout::Error
      raise "LLM request timed out after #{LLM_TIMEOUT}s"
    end

    private

    attr_reader :hotel, :message, :conversation_summary, :today

    def parse_fallback_response(raw)
      parsed = JSON.parse(raw.to_s)
      return parsed if Schemas::InterpretationSchema.new.valid?(parsed)

      default_interpretation
    rescue JSON::ParserError
      default_interpretation
    end

    def default_interpretation
      {
        "message_type" => "greeting_or_unknown",
        "intent" => "greeting",
        "topic" => "general",
        "confidence" => 0,
        "slots" => {},
        "tool_hints" => [],
        "conversation_signals" => {
          "is_reset" => false,
          "is_resume" => false,
          "is_correction" => false,
          "starts_new_booking_branch" => false,
          "end_conversation" => false
        }
      }
    end

    def prompt
      <<~PROMPT
        Classify the user message for AI Concierge.
        TODAY: #{today.iso8601}
        MESSAGE: "#{message}"
        SUMMARY: #{conversation_summary.to_json}

        ORDER OF WORK:
        1. Choose exactly one message_type.
        2. Map that message_type to intent/topic.
        3. Extract only slots relevant to that message_type.
        4. Set conversation_signals.

        MESSAGE TYPE DECISION TREE:
        - booking_request: user wants to search, book, reserve, quote, check availability, change booking dates, or continue booking slot collection.
          Relative timing like "this month", "late this month", "next month", and "late next month" is booking timing.
        - booking_selection: user chooses from shown booking options by option number, room type, shown date, or words like "that one". Use this when SUMMARY.booking_task.has_suggested_options is true and the message is selecting an option.
        - booking_confirmation: user answers yes/no to a pending booking confirmation, rate-plan confirmation, or party-split clarification. Use yes/no carefully based on SUMMARY.booking_task.pending_question.
        - hotel_info_question: user asks about hotel facts, facilities, amenities, services, parking, transportation, WiFi, breakfast, restaurant, spa, pool, or FAQ.
        - hotel_policy_question: user asks about policy, rules, house rules, check-in, check-out, cancellation, booking policy, or what to know/be aware of before/during booking.
        - room_info_question: user asks about room type details, room amenities, occupancy, or description, without clearly trying to book it.
        - existing_booking_question: user asks about an existing/current active booking.
        - conversation_control: user says stop, bye, thanks, end chat, reset, start over, nevermind, forget it, or another booking.
        - greeting_or_unknown: pure greeting or unclear message with no stronger type.

        MESSAGE TYPE TO INTENT/TOPIC:
        - booking_request -> intent=booking_search, topic=booking_search.
        - booking_selection -> intent=option_selection, topic=booking_search.
        - booking_confirmation -> intent=confirmation, topic=booking_search.
        - hotel_info_question -> intent=hotel_information, topic=general_hotel_info or hotel_faq.
        - hotel_policy_question -> intent=hotel_policy, topic=hotel_policy.
        - room_info_question -> intent=room_information, topic=room_information.
        - existing_booking_question -> intent=booking_context, topic=booking_context.
        - conversation_control -> use reset when resetting, otherwise use a generic intent with end_conversation=true when ending.
        - greeting_or_unknown -> intent=greeting, topic=general.

        CORE ROUTING RULES:
        - First prefer the guest's actual question over the previous booking flow.
        - If a booking is active but the message asks hotel, policy, room, or attraction info, use the information message type.
        - If the message returns to choosing options, dates, rate plans, or confirming a booking after an information interruption, use the matching booking message type.
        - Use nearby_attractions when the user asks about places to visit, nearby spots, attractions, or what is around the hotel.
        - Use greeting ONLY for pure greetings. If the message includes a greeting plus "can I book", use booking_request.
        - Set end_conversation=true for stop/bye/thanks/nevermind/forget it/end chat, but not for "no" rejecting a booking option.

        TOPIC RULES:
        - For hotel_policy intent, topic must be hotel_policy.
        - For nearby_attractions intent, topic must be nearby_attractions.
        - For hotel_information intent, use general_hotel_info for general hotel details and hotel_faq for FAQ-style hotel questions.
        - For room_information intent, topic must be room_information.
        - For booking_context intent, topic must be booking_context.
        - For booking_search, option_selection, and confirmation intents, topic should usually be booking_search.

        SLOT EXTRACTION RULES:
        - Extract dates, party size, option numbers, room type names, and rate plan names only when relevant to the chosen message_type.
        - Only set room_type_name when the user explicitly names or clearly refers to a room type.
        - If the user asks a vague room question without a room name, leave room_type_name null.
        - Never invent or normalize a room type name that was not clearly implied by the message.

        RATE PLAN EXTRACTION RULES:
        - If SUMMARY.booking_task.pending_question is "rate_plan_selection" and the user names a rate plan type such as "Standard Rate", "Non-Refundable", "the cheaper one", or "the standard one", extract the full rate plan name into rate_plan_name.
        - Only set rate_plan_name when the user is choosing a rate plan. Leave it null otherwise.
        - Match the full rate plan name as shown in the summary's rate plan options.
        - EXAMPLE: "standard rate" -> rate_plan_name="Standard Rate".
        - EXAMPLE: "the cheaper one" or "non refundable" -> rate_plan_name="Non-Refundable Rate" (use the exact name from the available rate plans in the summary).

        BOOKING VS INFORMATION CONTRAST RULES:
        - If the user asks about hotel amenities/facilities, prefer hotel_information.
        - If the user asks about room facts, named room amenities, or room description, prefer room_information.
        - If the user asks to book, select, reserve, confirm, or check availability for a room, prefer booking_search or option_selection.
        - "tell me about executive suite" -> message_type=room_info_question, intent=room_information.
        - "i want executive suite on may 22" -> message_type=booking_request, intent=booking_search.
        - ANY message selecting an option number (e.g., "option 1", "choice 2", "option 1 the executive one") MUST be classified as option_selection, NEVER room_information.
        - "what attractions are nearby" -> nearby_attractions, not hotel_information.
        - "what time is check in" -> hotel_policy, not hotel_information.
        - "booking policy" or "may I know the booking policy" -> hotel_policy, not booking_search.
        - "what should i aware during booking in this hotel?" -> hotel_policy, not booking_search.
        - "do you have house rules?" -> hotel_policy, not booking_search.
        - "tell me about the hotel" -> hotel_information with general_hotel_info.
        - "can i see hotel amenities" -> hotel_information with general_hotel_info.
        - "what amenities do you have" -> hotel_information with general_hotel_info unless a room type is named.
        - "may i know if the hotel provide transportation" -> hotel_information with general_hotel_info.
        - "is parking available there?" -> hotel_information with general_hotel_info.
        - "do you have an faq" -> hotel_information with hotel_faq.

        INTERRUPTION RULES:
        - If the conversation summary shows an active booking flow but the current message asks a hotel, room, or attraction question, classify the current message by its actual information intent instead of forcing booking_search.
        - If the message returns to choosing options, dates, or confirming a booking after an interruption, classify it back into booking_search, option_selection, or confirmation as appropriate.
        - If SUMMARY.booking_task.status="suspended" and SUMMARY.booking_task.pending_question="confirm_selection", classify clear yes/no replies as confirmation unless the message clearly asks a new information question.
        - If SUMMARY.booking_task.status="suspended" and SUMMARY.booking_task.pending_question="select_option", classify option numbers, room names, shown dates, or references like "that one" as option_selection unless the message clearly asks a new information question.
        - If SUMMARY.booking_task.status="suspended" and the user says something like "ok, I want to book on 23 june", classify it as booking_search and extract the date slots. Do not treat it as option_selection unless they choose from shown options.
        - If SUMMARY.booking_task.pending_question is "guest_count", a plain number is slot collection, not booking confirmation.
        - If SUMMARY.booking_task.pending_question is "confirm_selection", "yes" means booking_confirmation.

        - Use hotel_policy for operational policy questions like check-in, check-out, and cancellation.
        - Use hotel_information with topic general_hotel_info for general hotel details.
        - Use hotel_information with topic hotel_faq for FAQ-style hotel questions.
        - Use nearby_attractions with topic nearby_attractions for place or attraction questions.
        - Use room_information with topic room_information for room details.
        - IMPORTANT: If a slot is unknown, use null or 0. Never guess party size, timing, or duration.
        - IMPORTANT: Do NOT assume party_size_total=1 from singular pronouns like "I" or "me". Leave it null unless the user explicitly mentions the number of people.
        - IMPORTANT: Never invent target_month, target_year, month_segment, check_in, check_out, days, or nights from generic booking interest.
        - IMPORTANT: If the user only gives a month or month window like "May", leave check_in null. ONLY set check_in if an exact date is given.
        - IMPORTANT: If the user only mentions guest count or room interest, leave all timing slots null.
        - IMPORTANT: If the user only gives a month or month window like "early august", leave days, nights, and check_out null.
        - IMPORTANT: Only set month_segment when the message explicitly includes a month with words like early, mid, or late.
        - IMPORTANT: Only set target_month or target_year when the message explicitly includes a date, month, or window such as this month or next month.
        - IMPORTANT: Only set days or nights when the message explicitly mentions stay length.
        - IMPORTANT: Only set check_out when the message explicitly provides a checkout date or date range.
        - IMPORTANT: If the user says "2 people", set party_size_total=2 and leave adults and children null.
        - IMPORTANT: Do not convert "people" into adults unless the message explicitly says adults.
        - EXAMPLE: "any booking for 2 adults" -> no timing slots.
        - EXAMPLE: "need a room for 2" -> no timing slots.
        - EXAMPLE: "early august for 2 adults" -> target_month/target_year/month_segment set.
        - EXAMPLE: "early august" -> timing only, no days, nights, or check_out.
        - EXAMPLE: "late this month have?" -> message_type=booking_request, intent=booking_search, topic=booking_search, target_month/current year set, month_segment=late.
        - EXAMPLE: "early august for 3 days 2 nights" -> timing and duration set.
        - EXAMPLE: "early june for 2 people" -> party_size_total=2, adults=null, children=null.
        - EXAMPLE: "option 1 the executive one" -> intent=option_selection, topic=booking_search, option_number=1.
        - EXAMPLE: "august 3rd for 2 adults" -> explicit check_in set.
        - EXAMPLE: "what time is check in" -> intent=hotel_policy, topic=hotel_policy.
        - EXAMPLE: "before that, may I know the booking policy?" -> intent=hotel_policy, topic=hotel_policy.
        - EXAMPLE: "do you have house rules?" -> intent=hotel_policy, topic=hotel_policy.
        - EXAMPLE: "tell me about the hotel" -> intent=hotel_information, topic=general_hotel_info.
        - EXAMPLE: "may i know hotel amenities" -> intent=hotel_information, topic=general_hotel_info.
        - EXAMPLE: "may i know if the hotel provide transportation" -> intent=hotel_information, topic=general_hotel_info.
        - EXAMPLE: "is parking available there?" -> intent=hotel_information, topic=general_hotel_info.
        - EXAMPLE: "do you have faq" -> intent=hotel_information, topic=hotel_faq.
        - EXAMPLE: "what attractions are nearby" -> intent=nearby_attractions, topic=nearby_attractions.
        - EXAMPLE: "tell me about the executive suite" -> intent=room_information, topic=room_information, room_type_name="Executive Suite" if explicit.
        - EXAMPLE: "i want executive suite on may 22" -> booking_search or option_selection based on context, not room_information.
        - EXAMPLE: "can you show me nearby places" -> intent=nearby_attractions, topic=nearby_attractions.
        - EXAMPLE: "what are your hotel rules" -> intent=hotel_policy, topic=hotel_policy.
        - EXAMPLE: "what amenities does the executive suite have" -> intent=room_information, topic=room_information.
        - EXAMPLE: "during a booking flow, tell me about executive suite" -> intent=room_information, topic=room_information.
        - EXAMPLE: "after a room info answer, option 2 please" -> intent=option_selection, topic=booking_search.
        - EXAMPLE: "after a hotel info answer, ok i want to book on 23 june" -> intent=booking_search, topic=booking_search, check_in set.
        - EXAMPLE: "after a hotel info answer, yes" with suspended confirm_selection -> intent=confirmation, topic=booking_search, confirmation=yes.
        - EXAMPLE: "do you have parking?" -> message_type=hotel_info_question, intent=hotel_information, topic=general_hotel_info.
        - EXAMPLE: "booking policy?" -> message_type=hotel_policy_question, intent=hotel_policy, topic=hotel_policy.
        - EXAMPLE: "what should i aware during booking in this hotel?" -> message_type=hotel_policy_question, intent=hotel_policy, topic=hotel_policy.
        - EXAMPLE: "option 1 executive" -> message_type=booking_selection, intent=option_selection, topic=booking_search, option_number=1.
        - EXAMPLE: "yes" with pending_question=guest_count -> message_type=booking_request, intent=booking_search, no confirmation slot.
        - EXAMPLE: "yes" with pending_question=confirm_selection -> message_type=booking_confirmation, intent=confirmation, confirmation=yes.
        - Return strictly JSON.
      PROMPT
    end
    end
  end
end

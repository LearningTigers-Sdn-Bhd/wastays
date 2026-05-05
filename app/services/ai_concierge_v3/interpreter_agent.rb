require "ruby_llm"
require "ruby_llm/schema"

module AiConciergeV3
  class InterpreterAgent
    class InterpretationSchema < RubyLLM::Schema
      string :intent, enum: ["booking_search", "option_selection", "confirmation", "booking_context", "hotel_policy", "hotel_information", "nearby_attractions", "room_information", "greeting", "resume", "new_branch", "reset"]
      string :topic, enum: ["booking_search", "booking_context", "hotel_policy", "general_hotel_info", "hotel_faq", "nearby_attractions", "room_information", "room_type_faq", "general"]
      number :confidence
      object :slots do
        integer :target_month
        integer :target_year
        string :month_segment, enum: ["early", "mid", "late"]
        integer :nights
        integer :days
        integer :party_size_total
        integer :adults
        integer :children
        integer :room_count
        string :option_number
        string :confirmation, enum: ["yes", "no"]
        string :check_in
        string :check_out
        string :room_type_name
      end
      array :tool_hints do
        string enum: ["search_booking_options", "select_booking_option", "generate_booking_url", "get_hotel_policy", "get_booking_context", "get_general_hotel_info", "get_hotel_faq", "get_nearby_attractions", "get_room_type_details", "get_room_type_faq"]
      end
      object :conversation_signals do
        boolean :is_reset
        boolean :is_resume
        boolean :is_correction
        boolean :starts_new_booking_branch
      end
    end

    def initialize(hotel:, message:, conversation_summary:, today: Date.current)
      @hotel = hotel
      @message = message.to_s.strip
      @conversation_summary = conversation_summary || {}
      @today = today
    end

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

      response = chat.with_schema(InterpretationSchema).ask(prompt)
      response.content
    end

    private

    attr_reader :hotel, :message, :conversation_summary, :today

    def prompt
      <<~PROMPT
        Identify intent and slots from the user message.
        TODAY: #{today.iso8601}
        MESSAGE: "#{message}"
        SUMMARY: #{conversation_summary.to_json}

        DIRECTIONS:
        - Intent must be one of the enum values.
        - Extract dates, party size, option numbers, and room type names when the user asks about a room.
        - Map affirmative responses ("ok", "sure", "yes", "go ahead") to confirmation="yes".
        - Set conversation signals (is_reset, is_correction, etc.).
        - Choose the most specific intent that matches the user's request.

        INTENT ROUTING RULES:
        - Use confirmation when the user is approving or rejecting a shown booking option.
        - Use option_selection when the user is choosing from shown booking options by room type, option number, or shown date.
        - Use hotel_policy for operational policy questions such as check-in time, check-out time, cancellation, or hotel rules.
        - Use nearby_attractions for questions about places to visit, nearby spots, attractions, or what is around the hotel.
        - Use room_information for questions asking about a room type itself, such as details, amenities, occupancy, or room FAQ.
        - Use hotel_information for general hotel facts or hotel FAQ that are not specifically operational policy.
        - Use booking_context only when the user is asking about an existing active booking.
        - Use booking_search when the user is asking to find, start, continue, or modify a booking search.
        - Use greeting only for greetings or generic opening messages with no stronger intent.

        TOPIC RULES:
        - For hotel_policy intent, topic must be hotel_policy.
        - For nearby_attractions intent, topic must be nearby_attractions.
        - For hotel_information intent, use general_hotel_info for general hotel details and hotel_faq for FAQ-style hotel questions.
        - For room_information intent, use room_information for room details and room_type_faq for room FAQ questions.
        - For booking_context intent, topic must be booking_context.
        - For booking_search, option_selection, and confirmation intents, topic should usually be booking_search.

        ROOM TYPE EXTRACTION RULES:
        - Only set room_type_name when the user explicitly names or clearly refers to a room type.
        - If the user asks a vague room question without a room name, leave room_type_name null.
        - Never invent or normalize a room type name that was not clearly implied by the message.

        BOOKING VS INFORMATION CONTRAST RULES:
        - If the user asks about room facts, amenities, description, or FAQ, prefer room_information.
        - If the user asks to book, select, reserve, confirm, or check availability for a room, prefer booking_search or option_selection.
        - "tell me about executive suite" -> room_information.
        - "i want executive suite on may 22" -> booking_search or option_selection depending on context, not room_information.
        - "what attractions are nearby" -> nearby_attractions, not hotel_information.
        - "what time is check in" -> hotel_policy, not hotel_information.
        - "tell me about the hotel" -> hotel_information with general_hotel_info.
        - "do you have an faq" -> hotel_information with hotel_faq.

        INTERRUPTION RULES:
        - If the conversation summary shows an active booking flow but the current message asks a hotel, room, or attraction question, classify the current message by its actual information intent instead of forcing booking_search.
        - If the message returns to choosing options, dates, or confirming a booking after an interruption, classify it back into booking_search, option_selection, or confirmation as appropriate.

        - Use hotel_policy for operational policy questions like check-in, check-out, and cancellation.
        - Use hotel_information with topic general_hotel_info for general hotel details.
        - Use hotel_information with topic hotel_faq for FAQ-style hotel questions.
        - Use nearby_attractions with topic nearby_attractions for place or attraction questions.
        - Use room_information with topic room_information for room details and room_information with topic room_type_faq for room FAQ questions.
        - IMPORTANT: If a slot is unknown, use null or 0. Never guess party size, timing, or duration.
        - IMPORTANT: Never invent target_month, target_year, month_segment, check_in, check_out, days, or nights from generic booking interest.
        - IMPORTANT: If the user only mentions guest count or room interest, leave all timing slots null.
        - IMPORTANT: If the user only gives a month or month window like "early august", leave days, nights, and check_out null.
        - IMPORTANT: Only set month_segment when the message explicitly includes a month with words like early, mid, or late.
        - IMPORTANT: Only set target_month or target_year when the message explicitly includes a date, month, or window such as next month.
        - IMPORTANT: Only set days or nights when the message explicitly mentions stay length.
        - IMPORTANT: Only set check_out when the message explicitly provides a checkout date or date range.
        - IMPORTANT: If the user says "2 people", set party_size_total=2 and leave adults and children null.
        - IMPORTANT: Do not convert "people" into adults unless the message explicitly says adults.
        - EXAMPLE: "any booking for 2 adults" -> no timing slots.
        - EXAMPLE: "need a room for 2" -> no timing slots.
        - EXAMPLE: "early august for 2 adults" -> target_month/target_year/month_segment set.
        - EXAMPLE: "early august" -> timing only, no days, nights, or check_out.
        - EXAMPLE: "early august for 3 days 2 nights" -> timing and duration set.
        - EXAMPLE: "early june for 2 people" -> party_size_total=2, adults=null, children=null.
        - EXAMPLE: "august 3rd for 2 adults" -> explicit check_in set.
        - EXAMPLE: "what time is check in" -> intent=hotel_policy, topic=hotel_policy.
        - EXAMPLE: "tell me about the hotel" -> intent=hotel_information, topic=general_hotel_info.
        - EXAMPLE: "do you have faq" -> intent=hotel_information, topic=hotel_faq.
        - EXAMPLE: "what attractions are nearby" -> intent=nearby_attractions, topic=nearby_attractions.
        - EXAMPLE: "tell me about the executive suite" -> intent=room_information, topic=room_information, room_type_name="Executive Suite" if explicit.
        - EXAMPLE: "what is the faq for ocean villa king" -> intent=room_information, topic=room_type_faq, room_type_name="Ocean Villa King" if explicit.
        - EXAMPLE: "i want executive suite on may 22" -> booking_search or option_selection based on context, not room_information.
        - EXAMPLE: "can you show me nearby places" -> intent=nearby_attractions, topic=nearby_attractions.
        - EXAMPLE: "what are your hotel rules" -> intent=hotel_policy, topic=hotel_policy.
        - EXAMPLE: "what amenities does the executive suite have" -> intent=room_information, topic=room_information.
        - EXAMPLE: "during a booking flow, tell me about executive suite" -> intent=room_information, topic=room_information.
        - EXAMPLE: "after a room info answer, option 2 please" -> intent=option_selection, topic=booking_search.
        - Return strictly JSON.
      PROMPT
    end
  end
end

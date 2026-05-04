require "ruby_llm"
require "ruby_llm/schema"

module AiConciergeV3
  class InterpreterAgent
    class InterpretationSchema < RubyLLM::Schema
      string :intent, enum: ["booking_search", "option_selection", "confirmation", "booking_context", "hotel_policy", "greeting", "resume", "new_branch", "reset"]
      string :topic, enum: ["booking_search", "booking_context", "hotel_policy", "general"]
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
      end
      array :tool_hints do
        string enum: ["search_booking_options", "select_booking_option", "generate_booking_url", "get_hotel_policy", "get_booking_context"]
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
        - Extract dates, party size, option numbers.
        - Map affirmative responses ("ok", "sure", "yes", "go ahead") to confirmation="yes".
        - Set conversation signals (is_reset, is_correction, etc.).
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
        - Return strictly JSON.
      PROMPT
    end
  end
end

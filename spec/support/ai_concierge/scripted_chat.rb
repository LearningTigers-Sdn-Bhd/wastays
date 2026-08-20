# frozen_string_literal: true

# A RubyLLM::Chat that decides with ReferenceClassifier instead of a provider.
#
# It stands where the model stands, so everything below it -- tool dispatch,
# the halt, the hop cap, the recorder, the orchestrators -- is the real thing.
# Faking any lower would mean the agent_loop column tested the harness rather
# than the loop.
module AiConciergeEval
  class ScriptedChat
    def initialize(scripted_turns: {}, classifier_summary: {}, interpretation: nil)
      @scripted_turns = scripted_turns
      @classifier_summary = classifier_summary
      @interpretation = interpretation
      @tools = []
      @callbacks = Hash.new { |hash, key| hash[key] = [] }
    end

    # The chat-building surface RunTurn uses. Each returns self so the calls
    # chain the way RubyLLM's do.
    def with_instructions(*) = self

    def with_tools(*tools, **) = tap { @tools = tools.flatten }

    def with_temperature(*) = self
    def before_tool_call(&block) = tap { @callbacks[:before] << block }
    def after_tool_result(&block) = tap { @callbacks[:after] << block }

    def ask(message)
      call = tool_call_for(message)
      return Response.new(content: "Hello! How can I help you today?") unless call

      # `prose:` scripts the model reaching for no tool and answering in its
      # own words. Left to the classifier a fixture cannot express that, and
      # the guards that exist to catch it would have nothing to catch.
      return Response.new(content: call[:prose]) if call[:prose].present?

      tool = tools.find { |candidate| candidate.name == call.fetch(:tool) }
      raise ArgumentError, "fixture asked for unknown tool #{call[:tool]}" unless tool

      @callbacks[:before].each(&:call)
      result = tool.call(call[:arguments] || {})
      @callbacks[:after].each(&:call)
      result
    end

    private

    attr_reader :tools, :scripted_turns, :classifier_summary, :interpretation

    # A fixture that scripts a tool call gets exactly that. A spec that pins one
    # interpretation for the whole conversation gets that interpretation on every
    # turn. Otherwise the reference classifier decides. All three end up as the
    # tool a model holding that reading would have reached for.
    def tool_call_for(message)
      scripted = scripted_turns[message]
      return scripted if scripted

      ToolChoice.new(
        interpretation: interpretation || ReferenceClassifier.call(message: message, conversation_summary: classifier_summary),
        message: message
      ).call
    end

    Response = Struct.new(:content, keyword_init: true)

    class ToolChoice
      def initialize(interpretation:, message:)
        @interpretation = interpretation
        @message = message
      end

      def call
        case interpretation["intent"]
        when "hotel_policy"
          { tool: "answer_hotel_question", arguments: { "category" => "policy" } }
        when "hotel_information"
          { tool: "answer_hotel_question", arguments: { "category" => category_for_topic } }
        when "nearby_attractions"
          { tool: "get_nearby_attractions", arguments: {} }
        when "room_information"
          { tool: "get_room_type_details", arguments: room_arguments }
        when "booking_context"
          { tool: "get_booking_context", arguments: {} }
        when "booking_search", "option_selection", "confirmation", "reset"
          { tool: "advance_booking", arguments: booking_arguments }
        end
      end

      private

      attr_reader :interpretation, :message

      def category_for_topic = interpretation["topic"] == "hotel_faq" ? "faq" : "general_info"

      def room_arguments
        { "room_type_name" => interpretation.dig("slots", "room_type_name") }.compact
      end

      def booking_arguments
        {
          "slots" => interpretation["slots"].except("room_type_name").compact,
          "signals" => {
            "is_reset" => interpretation.dig("conversation_signals", "is_reset"),
            "starts_new_booking_branch" => interpretation.dig("conversation_signals", "starts_new_booking_branch")
          }
        }
      end
    end
  end
end

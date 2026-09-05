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
      @seeded_messages = []
      @callbacks = Hash.new { |hash, key| hash[key] = [] }
    end

    # The chat-building surface RunTurn uses. Each returns self so the calls
    # chain the way RubyLLM's do.
    def with_instructions(*) = self

    def with_tools(*tools, **) = tap { @tools = tools.flatten }

    def with_temperature(*) = self
    def before_tool_call(&block) = tap { @callbacks[:before] << block }
    def after_tool_result(&block) = tap { @callbacks[:after] << block }

    # Recorded rather than ignored so a spec can assert what the model was
    # shown. Inert to the decision: this chat picks its tool from the message
    # alone, which keeps every existing fixture answering exactly as before.
    def add_message(attributes) = tap { @seeded_messages << attributes }

    def ask(message)
      call = tool_call_for(message)
      return Response.new(content: "Hello! How can I help you today?") unless call

      # `prose:` scripts the model reaching for no tool and answering in its
      # own words. Left to the classifier a fixture cannot express that, and
      # the guards that exist to catch it would have nothing to catch.
      return Response.new(content: call[:prose]) if call[:prose].present?

      call = normalize_legacy_call(call, message)

      tool = tools.find { |candidate| candidate.name == call.fetch(:tool) }
      raise ArgumentError, "fixture asked for unknown tool #{call[:tool]}" unless tool

      @callbacks[:before].each(&:call)
      result = tool.call(call[:arguments] || {})
      @callbacks[:after].each(&:call)
      result
    end

    attr_reader :seeded_messages

    private

    attr_reader :tools, :scripted_turns, :classifier_summary, :interpretation

    def normalize_legacy_call(call, message)
      return call unless call[:tool].to_s.in?(%w[advance_booking answer_hotel_question get_nearby_attractions get_room_type_details])

      arguments = (call[:arguments] || {}).deep_symbolize_keys
      if call[:tool].to_s == "advance_booking"
        return {
          tool: "handle_guest_turn",
          arguments: {
            questions: [],
            commercial: {
              intent: "booking",
              slots: arguments[:slots] || {},
              signals: arguments[:signals] || {},
              evidence: arguments[:evidence] || {}
            }
          }
        }
      end

      kind, label, category = case call[:tool].to_s
      when "get_nearby_attractions" then [ "nearby_attractions", "Nearby attractions", "general_info" ]
      when "get_room_type_details" then [ "room_information", "Room", "general_info" ]
      else [ arguments[:category].to_s == "policy" ? "hotel_policy" : "hotel_information", "Hotel information", arguments[:category] || "general_info" ]
      end
      {
        tool: "handle_guest_turn",
        arguments: {
          questions: [
            {
              evidence: message,
              label: label,
              kind: kind,
              category: category,
              search_terms: arguments[:search_terms],
              fact: arguments[:fact],
              scope: arguments[:scope],
              room_type_name: arguments[:room_type_name]
            }.compact
          ],
          commercial: { intent: "none" }
        }
      }
    end

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
          information_call("hotel_policy", "Policy", "policy")
        when "hotel_information"
          information_call("hotel_information", "Hotel information", category_for_topic)
        when "nearby_attractions"
          information_call("nearby_attractions", "Nearby attractions", "general_info")
        when "room_information"
          information_call("room_information", "Room", "general_info", room_type_name: room_arguments["room_type_name"])
        when "booking_context"
          { tool: "get_booking_context", arguments: {} }
        when "booking_search", "option_selection", "confirmation", "reset"
          { tool: "handle_guest_turn", arguments: { questions: [], commercial: { intent: "booking" }.merge(booking_arguments) } }
        end
      end

      private

      attr_reader :interpretation, :message

      def category_for_topic = interpretation["topic"] == "hotel_faq" ? "faq" : "general_info"

      def information_call(kind, label, category, room_type_name: nil)
        hints = interpretation["retrieval_hints"].is_a?(Hash) ? interpretation["retrieval_hints"] : {}
        {
          tool: "handle_guest_turn",
          arguments: {
            questions: [
              {
                evidence: message,
                label: label,
                kind: kind,
                category: category,
                search_terms: Array(hints["terms"]).join(" ").presence,
                fact: hints["fact"],
                scope: interpretation["scope"],
                room_type_name: room_type_name
              }.compact
            ],
            commercial: { intent: "none" }
          }
        }
      end

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

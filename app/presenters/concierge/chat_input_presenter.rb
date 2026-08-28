# frozen_string_literal: true

module Concierge
  class ChatInputPresenter
    Suggestion = Struct.new(:label, :kind, :value, keyword_init: true)

    GROUPS = {
      "greeting" => [
        [ "Find a room", :message, "I want to find a room." ],
        [ "Check prices", :message, "I want to check prices." ],
        [ "Manage my booking", :message, "I want to manage my booking." ],
        [ "Ask about the hotel", :message, "Tell me about the hotel." ]
      ],
      "portal_offer" => [
        [ "Send login link", :message, "Send my login link." ],
        [ "Ask the hotel team", :agent, nil ],
        [ "Not now", :message, "Not now." ]
      ],
      "post_link_sales" => [
        [ "Find a room", :message, "I want to find a room." ],
        [ "Check prices", :message, "I want to check prices." ],
        [ "Explore the hotel", :message, "Tell me about the hotel." ],
        [ "Not now", :message, "Not now." ]
      ],
      "magic_link_failure" => [
        [ "Ask the hotel team", :agent, nil ],
        [ "Ask another question", :focus, nil ],
        [ "Not now", :message, "Not now." ]
      ],
      "staff_wait" => [
        [ "Find the right room", :message, "I want to find a room." ],
        [ "Check current prices", :message, "I want to check prices." ],
        [ "Explore the hotel", :message, "Tell me about the hotel." ],
        [ "Discover nearby places", :message, "What places are nearby?" ],
        [ "I will wait", :message, "I will wait." ]
      ],
      "unsupported_change" => [
        [ "Ask the hotel team", :agent, nil ],
        [ "Ask another question", :focus, nil ],
        [ "Explore the hotel", :message, "Tell me about the hotel." ],
        [ "Not now", :message, "Not now." ]
      ]
    }.freeze

    attr_reader :conversation

    def initialize(conversation:, error: nil)
      @conversation = conversation
      @error = error
    end

    def kind
      return :message unless conversation
      return :confirmation_code if task_manager.existing_booking_pending?(conversation_id: conversation.id)

      :message
    end

    def suggestions
      return [] unless conversation

      Array(GROUPS[task_manager.suggestion_group]).map do |label, kind, value|
        Suggestion.new(label: label, kind: kind, value: value)
      end
    end

    def error
      @error
    end

    private

    def task_manager
      @task_manager ||= AiConcierge::State::ConversationTaskManager.new(
        slots_payload: conversation.prospect.prospect_conversation_state&.slots_payload
      )
    end
  end
end

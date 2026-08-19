# frozen_string_literal: true

module PublicUI
  module Chat
    # The scrollable thread.
    #
    # The list is rendered even with nothing in it: it is the anchor a live
    # message gets appended to, and an element that only exists once there is
    # already a message is no anchor at all.
    #
    # Consecutive messages from the same author are grouped into a run, so three
    # answers in a row read as one person still talking rather than three
    # strangers who happen to share a name.
    class Log < PublicUI::BaseComponent
      include ChatMessageRuns

      DEFAULT_ID = "concierge-chat-log"
      DEFAULT_EMPTY_TEXT = "Ask about rooms, rates, facilities or anything else about your stay."

      def initialize(messages:, hotel:, id: DEFAULT_ID, label: "Conversation",
                     empty_text: DEFAULT_EMPTY_TEXT, class: nil, **attributes)
        @messages = messages.to_a
        @hotel = hotel
        @id = id
        @label = label
        @empty_text = empty_text
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def call
        safe_join([ empty_state, list ].compact)
      end

      private

      def empty_state
        return if @messages.any?

        tag.p(@empty_text, id: "#{@id}-empty", class: "public-chat__empty")
      end

      def list
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || {}

        tag.ol(**attributes.merge(
          id: @id,
          class: tw_merge("public-chat__log", @class),
          role: "log",
          aria: { label: @label, live: "polite" },
          data: data.merge(
            concierge_chat_target: "log",
            more_above: "false",
            action: "scroll->concierge-chat#markScrollPosition"
          )
        )) do
          safe_join(bubbles)
        end
      end

      def bubbles
        message_runs(@messages).map do |message, run|
          render Message.new(message: message, hotel: @hotel, **run)
        end
      end
    end
  end
end

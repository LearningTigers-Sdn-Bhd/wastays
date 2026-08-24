# frozen_string_literal: true

module HotelPortal
  module Inbox
    # The thread of messages in one conversation.
    #
    # Rendered even when empty: it is the anchor a live message gets appended to,
    # and its id is what ProspectMessage broadcasts at, so it has to exist before
    # there is anything in it.
    #
    # Consecutive messages from one author are grouped into a run, so three
    # assistant answers in a row read as the assistant still talking rather than
    # three separate replies each restating the name and the time.
    class Log < PanelsUI::BaseComponent
      include ChatMessageRuns

      style base: "space-y-3 p-4"

      def self.dom_id_for(conversation) = ActionView::RecordIdentifier.dom_id(conversation, :messages)

      def initialize(conversation:, messages:, label: "Conversation", class: nil, **attributes)
        @conversation = conversation
        @messages = messages.to_a
        @label = label
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def call
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || {}

        tag.ol(**attributes.merge(
          id: self.class.dom_id_for(@conversation),
          class: class_for(class_override: @class),
          role: "log",
          aria: { label: @label, live: "polite" },
          data: data.merge(concierge_chat_target: "log")
        )) do
          safe_join(bubbles)
        end
      end

      private

      def bubbles
        message_runs(@messages).map do |message, run|
          render Message.new(message: message, **run)
        end
      end
    end
  end
end

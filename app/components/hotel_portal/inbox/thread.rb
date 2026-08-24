# frozen_string_literal: true

module HotelPortal
  module Inbox
    # One open conversation: who it is with, what has been said, and the box to
    # answer in.
    #
    # Owns the card's height contract as well as its parts. The card is exactly
    # as tall as the pane it sits in, the header, mode bar and composer hold
    # their size, and the thread takes what is left and scrolls inside it --
    # which only works if one object decides all four, so a page cannot compose
    # the pieces into a card that pushes its own composer off the bottom.
    class Thread < PanelsUI::BaseComponent
      style base: "flex h-full flex-col overflow-hidden rounded-xl border border-border bg-card"

      def initialize(conversation:, messages:, hotel:, class: nil, **attributes)
        @conversation = conversation
        @messages = messages
        @hotel = hotel
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def root_attributes
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || {}

        attributes.merge(
          class: class_for(class_override: @class),
          data: data.reverse_merge(controller: "concierge-chat")
        )
      end

      def presenter = @presenter ||= helpers.conversation_presenter(@conversation)

      private

      attr_reader :conversation, :messages, :hotel

      def badge = presenter.status_badge
    end
  end
end

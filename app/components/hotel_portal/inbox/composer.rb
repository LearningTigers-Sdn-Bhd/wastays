# frozen_string_literal: true

module HotelPortal
  module Inbox
    # The reply box, offered only where a reply actually arrives.
    #
    # A WhatsApp thread still has no outbound route, so it gets the honest notice
    # instead of a box that would file what someone wrote and never send it.
    #
    # Stable id for the same reason as the mode bar: closing or reopening a
    # thread from another screen changes what belongs here.
    class Composer < PanelsUI::BaseComponent
      style base: "shrink-0 border-t border-border p-4"

      def self.dom_id_for(conversation) = ActionView::RecordIdentifier.dom_id(conversation, :composer)

      def initialize(conversation:, hotel:, class: nil, **attributes)
        @conversation = conversation
        @hotel = hotel
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def root_attributes
        @attributes.merge(
          id: self.class.dom_id_for(@conversation),
          class: class_for(class_override: @class)
        )
      end

      private

      attr_reader :conversation, :hotel

      def closed? = !conversation.open?
      def deliverable? = conversation.replies_reach_guest?
      def channel_label = helpers.conversation_presenter(conversation).channel_label
    end
  end
end

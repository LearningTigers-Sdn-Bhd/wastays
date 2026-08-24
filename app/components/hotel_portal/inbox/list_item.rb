# frozen_string_literal: true

module HotelPortal
  module Inbox
    # One row in the conversation list.
    #
    # The row itself carries only which thread it is and whether this reader has
    # it open -- both of which a broadcast must not touch. Everything a message
    # can change lives inside it, in ListItemBody, so the inbox can be kept
    # current for everyone without any of them losing their place.
    class ListItem < PanelsUI::BaseComponent
      style variants: { selected: { on: "block bg-muted", off: "block" } },
            defaults: { selected: :off }

      def self.dom_id_for(conversation) = ActionView::RecordIdentifier.dom_id(conversation, :row)

      def initialize(conversation:, hotel:, selected: false, class: nil, **attributes)
        @conversation = conversation
        @hotel = hotel
        @selected = selected
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      # aria-current sits on the row rather than on the link inside it for the
      # same reason the highlight does: it says something about this reader, and
      # the link is what a broadcast replaces.
      def call
        tag.li(**@attributes.merge(
          id: self.class.dom_id_for(@conversation),
          class: class_for(selected: (@selected ? :on : :off), class_override: @class),
          aria: { current: (@selected ? "true" : nil) }.compact
        )) do
          render ListItemBody.new(conversation: @conversation, hotel: @hotel)
        end
      end
    end
  end
end

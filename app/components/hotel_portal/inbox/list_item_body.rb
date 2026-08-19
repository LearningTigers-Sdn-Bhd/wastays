# frozen_string_literal: true

module HotelPortal
  module Inbox
    # What one row in the conversation list actually says.
    #
    # Split from the row itself so a broadcast can refresh what the row says --
    # unread marker, status, when the guest last wrote -- without touching the
    # row. Which row is open is the one thing about the list that is true for
    # one reader and false for everybody else, and it lives on the wrapper: a
    # broadcast that replaced the whole row would un-highlight the thread the
    # reader is sitting in.
    class ListItemBody < PanelsUI::BaseComponent
      style base: "flex w-full flex-col gap-1.5 px-3 py-3 text-left transition hover:bg-muted " \
                  "focus-visible:bg-muted focus-visible:outline-none"

      def initialize(conversation:, hotel:, class: nil, **attributes)
        @conversation = conversation
        @hotel = hotel
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def presenter = @presenter ||= helpers.conversation_presenter(@conversation)
      def link_class = class_for(class_override: @class)

      private

      attr_reader :hotel

      def badge = presenter.status_badge
    end
  end
end

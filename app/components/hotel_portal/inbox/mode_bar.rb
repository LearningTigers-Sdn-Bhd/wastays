# frozen_string_literal: true

module HotelPortal
  module Inbox
    # Who is answering this conversation, and the one move that changes it.
    #
    # Carries a stable id because mode is the column two people can disagree
    # about: a colleague taking the thread over on their own screen has to be
    # able to replace this strip on everyone else's.
    #
    # Each button is its own form rather than a link with a method, so nothing
    # here changes a conversation on a crawler's GET.
    class ModeBar < PanelsUI::BaseComponent
      style base: "flex shrink-0 flex-wrap items-center gap-2 border-b border-border bg-muted/40 px-4 py-2.5"

      def self.dom_id_for(conversation) = ActionView::RecordIdentifier.dom_id(conversation, :mode_bar)

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

      def bot_holding? = conversation.bot?
      def assistant_available? = hotel.ai_concierge_ready?
    end
  end
end

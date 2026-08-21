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
      def presenter = @presenter ||= helpers.conversation_presenter(conversation)
      def channel_label = presenter.channel_label

      # How the reply travels, said plainly, because the two routes behave
      # differently enough to matter: a web guest has the reply before the page
      # settles, a WhatsApp guest gets it whenever the relay sends it on -- and
      # only for as long as WhatsApp still carries one.
      def delivery_note
        return "The guest sees this on their chat page straight away." if conversation.channel == "web"

        [ "Sent to the guest on #{channel_label}.", window_note ].compact.join(" ")
      end

      def window_note
        label = presenter.reply_window_label

        "#{label} to reply." if label.present?
      end

      # A lapsed window is not the same refusal as a channel with no route out.
      # Nothing is missing here and nothing needs connecting -- the clock ran
      # out, and only the guest writing again restarts it -- so it says so, and
      # says it as a warning rather than as information about the product.
      def window_lapsed? = conversation.reply_blocker == :window_lapsed

      def blocker_title
        return "The 24-hour reply window on this thread has closed" if window_lapsed?

        "You cannot reply to #{channel_label} here yet"
      end

      def blocker_tone = window_lapsed? ? :warning : :info
    end
  end
end

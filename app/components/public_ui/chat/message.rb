# frozen_string_literal: true

module PublicUI
  module Chat
    # One message in the guest-facing thread.
    #
    # The single renderer for a message on the guest side: the page loop and a
    # Turbo Stream append both go through here, so a live message cannot come out
    # looking different from one that was on the page when it loaded.
    #
    # A message knows where it sits in a run of consecutive messages from the same
    # author, because that is what decides whether it repeats the name above it and
    # whether it is the one that carries the tail. Both default to true: a message
    # rendered on its own -- an append, a preview -- is a run of one.
    class Message < PublicUI::BaseComponent
      SIDES = { "guest" => :guest, "bot" => :hotel, "staff" => :staff, "system" => :system }.freeze

      def initialize(message:, hotel:, first_in_run: true, last_in_run: true, class: nil, **attributes)
        @message = message
        @hotel = hotel
        @first_in_run = first_in_run
        @last_in_run = last_in_run
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def call
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || {}

        tag.li(**attributes.merge(
          id: attributes[:id] || ActionView::RecordIdentifier.dom_id(@message),
          class: tw_merge("public-chat__message", @class),
          data: data.merge(
            side: side,
            run_start: @first_in_run.to_s,
            run_end: @last_in_run.to_s
          )
        )) do
          safe_join([ author_label, bubble ].compact)
        end
      end

      private

      def side = SIDES.fetch(@message.sender_role, :hotel)

      # A system line ("a team member joined") is narration, not something anyone
      # said, so it carries no name. Nor does a message that continues a run --
      # the name is already above it.
      def author_label
        return if side == :system || !@first_in_run

        tag.span(author, class: "public-chat__author")
      end

      def author
        return "You" if side == :guest

        helpers.concierge_reply_author(@message, @hotel)
      end

      # Built in Ruby rather than ERB on purpose: the bubble is whitespace-pre-wrap,
      # so template indentation around the body would render as a literal indent.
      def bubble = tag.div(@message.body, class: "public-chat__bubble")
    end
  end
end

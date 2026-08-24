# frozen_string_literal: true

module HotelPortal
  module Inbox
    # One message in the staff-facing thread.
    #
    # The single renderer for a message in the inbox: the page loop and a Turbo
    # Stream append both go through here, so a message that arrives live cannot
    # come out looking different from one that was on the page already.
    #
    # Four sides, not two. Reading down a thread, the question a staff member is
    # actually asking is "has a person already answered this, or is that still
    # the assistant" -- so the bot and a colleague cannot share a bubble. And a
    # system line is narration about the conversation, not something the hotel
    # said in it, so it does not get a side at all.
    #
    # Deliberately not dressed like the guest's chat: that page is outside
    # DESIGN.md and has its own soft, tailed, uppercase language. This one is
    # read fifty threads a day and keeps the portal's tighter character.
    class Message < PanelsUI::BaseComponent
      SIDES = { "guest" => :guest, "bot" => :bot, "staff" => :staff, "system" => :system }.freeze

      BUBBLE_BASE = "max-w-[85%] whitespace-pre-wrap rounded-lg px-3 py-2 text-sm"
      BUBBLE_SIDES = {
        guest: "bg-muted text-foreground",
        bot: "bg-primary text-primary-foreground",
        staff: "bg-accent text-accent-foreground",
        system: "max-w-full rounded-none bg-transparent px-0 py-0 text-center text-xs italic text-muted-foreground"
      }.freeze

      style base: "flex flex-col gap-1",
            variants: {
              side: {
                guest: "items-start",
                bot: "items-end",
                staff: "items-end",
                system: "items-center"
              }
            },
            defaults: { side: :bot }

      def initialize(message:, first_in_run: true, last_in_run: true, class: nil, **attributes)
        @message = message
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
          class: class_for(side: side, class_override: @class),
          data: data.merge(
            side: side,
            run_start: @first_in_run.to_s,
            run_end: @last_in_run.to_s
          )
        )) do
          safe_join([ author_label, bubble, source_disclosure ].compact)
        end
      end

      private

      def side = SIDES.fetch(@message.sender_role, :bot)

      # Who wrote it is carried by the name above the bubble, never by which side
      # it sits on or what colour it is -- that would be meaning conveyed by
      # position and colour alone (DESIGN.md §10).
      #
      # A system line carries no name because nobody said it, and a message
      # continuing a run carries none because the name is already above it.
      def author_label
        return if side == :system || !@first_in_run

        tag.span(class: "px-1 text-xs text-muted-foreground") do
          safe_join([ author, separator, timestamp ].compact)
        end
      end

      def author = helpers.conversation_message_author(@message)

      def separator
        return if @message.sent_at.blank?

        tag.span(" · ", aria: { hidden: "true" })
      end

      def timestamp
        return if @message.sent_at.blank?

        tag.time(helpers.l(@message.sent_at, format: :short), datetime: @message.sent_at.iso8601)
      end

      # Built in Ruby rather than ERB on purpose: the bubble is whitespace-pre-wrap,
      # so template indentation around the body would render as a literal indent.
      def bubble = tag.div(@message.body, class: tw_merge(BUBBLE_BASE, BUBBLE_SIDES.fetch(side)))

      # What the assistant computed, before it was rewritten in the guest's
      # language. Only present on a message the stylist actually replaced.
      #
      # Folded away rather than shown, because the thread is what the guest
      # read: a staff member scanning it should see the conversation, and reach
      # for the English only when the language in front of them is not one they
      # have.
      def source_disclosure
        return if @message.source_body.blank?

        render PanelsUI::Collapsible.new(
          id: "#{ActionView::RecordIdentifier.dom_id(@message)}-source",
          class: "max-w-[85%]",
          trigger_class: "text-xs text-muted-foreground",
          content_class: "pt-1",
          region: true
        ) do |collapsible|
          collapsible.with_trigger { "Show original" }
          collapsible.with_body do
            tag.p(@message.source_body, class: "whitespace-pre-wrap rounded-lg bg-muted px-3 py-2 text-xs text-muted-foreground")
          end
        end
      end
    end
  end
end

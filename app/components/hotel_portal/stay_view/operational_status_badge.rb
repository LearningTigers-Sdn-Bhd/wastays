# frozen_string_literal: true

module HotelPortal
  module StayView
    # One dominant operational status per room, matching the toolbar legend
    # (Vacant / Reserved / Occupied / Due out / Blocked). Collapsed states expose
    # the detail they stand in for through a hover/focus popover:
    #   - Due out reveals the occupied stay checking out.
    #   - Blocked reveals the maintenance / out-of-service block.
    class OperationalStatusBadge < PanelsUI::BaseComponent
      POPOVER_STATES = %i[due_out blocked].freeze

      def initialize(room:, status:, reference_date:)
        @room = room
        @status = status.to_sym
        @reference_date = reference_date.to_date
      end

      def before_render
        raise ArgumentError, "OperationalStatusBadge requires a StayView::RoomRow" unless @room.is_a?(::StayView::RoomRow)
      end

      def call
        POPOVER_STATES.include?(@status) ? badge_with_details : badge
      end

      private

      def presentation
        OperationalCounts::PRESENTATION.fetch(@status)
      end

      def badge(**attributes)
        render PanelsUI::Badge.new(
          label: presentation.fetch(:label),
          variant: presentation.fetch(:variant),
          size: :sm,
          indicator: true,
          data: { slot: "stay-view-operational-status", status: @status },
          **attributes
        )
      end

      def badge_with_details
        render PanelsUI::Popover.new(
          id: "#{@room.dom_id}-operational-status",
          placement: :bottom_start,
          trigger_on: :hover,
          close_delay: 120,
          class: "w-64 p-3"
        ) do |popover|
          popover.with_trigger(unstyled: true, aria_label: accessible_label, class: "inline-flex rounded-full") do
            badge(aria: { hidden: true })
          end
          details_content
        end
      end

      def details_content
        @status == :blocked ? blocked_details : due_out_details
      end

      def blocked_details
        tag.div(class: "space-y-2 text-left") do
          safe_join([
            tag.p("Blocked", class: "text-sm font-semibold text-foreground"),
            tag.ul(class: "space-y-1", aria: { label: "Active room blocks" }) do
              safe_join(@room.operational_segments.map do |segment|
                tag.li(class: "text-xs text-foreground") do
                  safe_join([
                    tag.span(segment.label, class: "font-medium"),
                    tag.span("#{segment.start_date.to_fs(:medium)} – #{segment.end_date.to_fs(:medium)}", class: "block text-muted-foreground")
                  ])
                end
              end)
            end
          ])
        end
      end

      def due_out_details
        tag.div(class: "space-y-2 text-left") do
          safe_join([
            tag.div do
              safe_join([
                tag.p("Due out", class: "text-sm font-semibold text-foreground"),
                tag.p(due_out_description, class: "text-xs text-muted-foreground")
              ])
            end,
            due_out_bookings
          ].compact)
        end
      end

      def due_out_bookings
        return if due_out_segments.empty?

        tag.ul(class: "space-y-1", aria: { label: "Stays checking out" }) do
          safe_join(due_out_segments.map do |segment|
            tag.li(class: "text-xs text-foreground") do
              safe_join([
                tag.span(segment.guest_label, class: "font-medium"),
                tag.span("Checkout #{segment.check_out.to_fs(:medium)}", class: "block text-muted-foreground")
              ])
            end
          end)
        end
      end

      def accessible_label
        base = "Room status: #{presentation.fetch(:label)}"
        details = case @status
        when :blocked then @room.operational_segments.map(&:label).to_sentence.presence
        when :due_out then due_out_segments.map(&:guest_label).to_sentence.presence || "Late checkout detected"
        end
        details ? "#{base} — #{details}" : base
      end

      def due_out_segments
        @due_out_segments ||= @room.booking_segments.select do |segment|
          ::StayView::CalculateCounts::DUE_OUT_STATUSES.include?(segment.status) && segment.check_out <= @reference_date
        end
      end

      def due_out_description
        due_out_segments.empty? ? "Late checkout detected" : "Occupied stay checking out"
      end
    end
  end
end

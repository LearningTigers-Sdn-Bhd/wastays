# frozen_string_literal: true

module HotelPortal
  module StayView
    class BookingBar < PanelsUI::BaseComponent
      STATUS_TONES = {
        pending: :neutral,
        confirmed: :info,
        review_no_show: :info,
        checked_in: :success,
        review_due_out: :success,
        checkout_required: :success,
        cancelled: :destructive,
        completed: :completed,
        overbooked: :destructive,
        no_show: :destructive
      }.freeze
      GUEST_STATUS_PRESENTATIONS = {
        "Blacklisted" => { icon: "ban", class: "text-destructive" }.freeze,
        "VIP" => { icon: "crown-simple", class: "text-warning", library: "phosphor", variant: "duotone" }.freeze,
        "Repeat" => { icon: "repeat", class: "text-info" }.freeze
      }.freeze

      def initialize(segment:, href: nil, id: nil, class: nil, link_attributes: {}, interaction: {}, **attributes)
        @segment = segment
        @href = href
        @id = id
        @class = binding.local_variable_get(:class)
        @link_attributes = link_attributes
        @interaction = interaction
        @attributes = attributes
      end

      def before_render
        unless @segment.is_a?(::StayView::BookingSegment)
          raise ArgumentError, "BookingBar requires a StayView::BookingSegment"
        end
      end

      def call
        render PanelsUI::Popover.new(
          id: @id.presence || @segment.dom_id,
          placement: :top,
          trigger_on: :hover,
          close_delay: 120,
          class: "w-80 p-3",
          root_class: tw_merge("panel-timeline__segment", @class),
          style: "grid-column: #{@segment.start_track} / #{@segment.end_track}",
          data: segment_data,
          **@attributes
        ) do |popover|
          popover.with_trigger(**trigger_attributes) do
            safe_join([
              resize_handle(:start),
              tag.span(@segment.guest_label, class: "stay-view-booking-guest-name min-w-0 flex-1 truncate"),
              booking_source,
              resize_handle(:end)
            ].compact)
          end
          popover_content
        end
      end

      private

      def permitted_href
        @href if @href.present? && @segment.capabilities.view_booking?
      end

      def segment_data
        data = {
          slot: "timeline-segment",
          tone: STATUS_TONES.fetch(@segment.status, :neutral),
          emphasis: :solid,
          clipped_left: @segment.clipped_left?.to_s,
          clipped_right: @segment.clipped_right?.to_s
        }
        return data unless interactive?

        data.merge(
          "stay-view--interaction-target": "segment",
          action: "pointerdown->stay-view--interaction#start",
          booking_id: @segment.booking_id,
          booking_room_id: @segment.booking_room_id,
          check_in: @segment.check_in.iso8601,
          check_out: @segment.check_out.iso8601,
          room_type_id: @interaction[:room_type_id],
          room_number: @interaction[:room_number],
          move_url: @interaction[:move_url],
          dates_url: @interaction[:dates_url]
        ).compact
      end

      def trigger_attributes
        attributes = @link_attributes.deep_dup
        aria = attributes.delete(:aria) || attributes.delete("aria") || {}
        attributes.merge(
          href: permitted_href,
          draggable: false,
          unstyled: true,
          class: tw_merge(
            "panel-timeline__segment-content gap-2",
            ("panel-timeline__segment-action" if permitted_href),
            attributes.delete(:class)
          ),
          aria_label: aria.delete(:label) || aria.delete("label") || @segment.accessible_label,
          aria:
        )
      end

      def interactive?
        @interaction[:move_url].present? || @interaction[:dates_url].present?
      end

      def resize_handle(edge)
        return unless @interaction[:dates_url].present?
        return if edge == :start && @segment.clipped_left?
        return if edge == :end && @segment.clipped_right?

        tag.span(
          "",
          class: "panel-timeline__resize-handle",
          aria: { hidden: true },
          data: {
            "stay-view--interaction-target": "handle",
            resize_edge: edge
          }
        )
      end

      def popover_content
        tag.div(class: "space-y-3 text-left") do
          safe_join([ popover_heading, popover_details, group_rooms ].compact)
        end
      end

      def popover_heading
        tag.div do
          safe_join([
            tag.div(class: "flex min-w-0 items-center gap-1.5") do
              safe_join([
                tag.p(@segment.primary_guest_name, class: "min-w-0 truncate text-sm font-semibold text-foreground"),
                guest_status_indicators
              ].compact)
            end,
            tag.p(@segment.booking_type == :group ? "Group booking" : "Single booking", class: "text-xs text-muted-foreground")
          ])
        end
      end

      def popover_details
        tag.dl(class: "grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs") do
          rows = [
            [ "Status", @segment.status.to_s.humanize ],
            [ "Stay", "#{@segment.check_in.to_fs(:medium)} – #{@segment.check_out.to_fs(:medium)}" ]
          ]
          rows << [ "Source", source_value ] if @segment.source_label.present?
          @segment.financial_signals.each { |signal| rows << [ "Financial", signal.label ] }
          rows << [ "Group", [ @segment.group_name, @segment.group_reference ].compact_blank.join(" · ") ] if @segment.group_reference.present?
          safe_join(rows.flat_map { |label, value| [ tag.dt(label, class: "text-muted-foreground"), tag.dd(value, class: "text-foreground") ] })
        end
      end

      def source_value
        return @segment.source_label if @segment.source.blank?

        tag.span(class: "inline-flex items-center gap-1.5") do
          safe_join([
            render(PanelsUI::BookingSourceBadge.new(source: @segment.source, size: :sm, with_tooltip: false)),
            @segment.source_label
          ])
        end
      end

      def guest_status_icon_options(presentation)
        { class: "size-3.5", aria: { hidden: true } }
          .merge(presentation.slice(:library, :variant))
      end

      def guest_status_indicators
        return if @segment.guest_statuses.empty?

        tag.span(class: "flex shrink-0 items-center gap-1", data: { slot: "stay-view-guest-statuses" }) do
          safe_join(@segment.guest_statuses.map do |status|
            presentation = GUEST_STATUS_PRESENTATIONS.fetch(status)
            tag.span(
              helpers.app_icon(presentation.fetch(:icon), **guest_status_icon_options(presentation)),
              class: presentation.fetch(:class),
              role: "img",
              aria: { label: "#{status} guest" },
              data: { slot: "stay-view-guest-status", status: status.downcase }
            )
          end)
        end
      end

      def booking_source
        return if @segment.source.blank?

        tag.span(class: "ml-auto shrink-0", data: { slot: "stay-view-booking-source" }) do
          render PanelsUI::BookingSourceBadge.new(
            source: @segment.source,
            size: :sm,
            with_tooltip: false,
            decorative: true
          )
        end
      end

      def group_rooms
        return if @segment.group_rooms.empty?

        tag.div(class: "border-t border-border pt-2") do
          safe_join([
            tag.p("Other rooms", class: "text-xs font-medium text-foreground"),
            tag.ul(class: "mt-1 space-y-1 text-xs text-muted-foreground") do
              safe_join(@segment.group_rooms.map { |room| tag.li("#{room.room_number} – #{room.room_type_name}") })
            end
          ])
        end
      end
    end
  end
end

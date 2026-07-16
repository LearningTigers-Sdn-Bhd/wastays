# frozen_string_literal: true

module HotelPortal
  module StayView
    class OperationalIndicators < PanelsUI::BaseComponent
      def initialize(room:, class: nil, **attributes)
        @room = room
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def before_render
        raise ArgumentError, "OperationalIndicators requires a StayView::RoomRow" unless @room.is_a?(::StayView::RoomRow)
      end

      def call
        return if indicators.empty?

        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || {}
        aria = attributes.delete(:aria) || {}
        tag.div(
          safe_join(indicators),
          **attributes.merge(
            class: tw_merge("flex items-center gap-1", @class, attributes.delete(:class)),
            data: data.merge(slot: "stay-view-operational-indicators"),
            aria: aria.merge(label: "Current operational indicators for room #{@room.room_number}")
          )
        )
      end

      private

      def indicators
        @indicators ||= [
          (flag_badge(:dnd, "Do not disturb", "door-closed", :warning) if @room.operational_flags[:dnd]),
          (flag_badge(:priority, "Priority room", "flag", :destructive) if @room.operational_flags[:priority]),
          housekeeping_popover
        ].compact
      end

      def flag_badge(key, label, icon, variant)
        render PanelsUI::Tooltip.new(text: label, id: "#{@room.dom_id}-#{key}-tooltip") do
          render PanelsUI::Badge.new(
            variant:,
            size: :sm,
            shape: :rounded,
            role: "img",
            tabindex: 0,
            aria: { label: label }
          ) do
            helpers.app_icon(icon, class: "size-3", aria: { hidden: true })
          end
        end
      end

      def housekeeping_popover
        return if @room.housekeeping_alerts.empty?

        count = @room.housekeeping_alerts.size
        label = helpers.pluralize(count, "active housekeeping request")
        render PanelsUI::Popover.new(
          id: "#{@room.dom_id}-housekeeping",
          placement: :bottom_end,
          class: "w-72 p-3",
          focus: true
        ) do |popover|
          popover.with_trigger(unstyled: true, aria_label: label, class: "inline-flex rounded-full") do
            render PanelsUI::Badge.new(variant: :info, size: :sm, shape: :rounded, class: "gap-1", aria: { hidden: true }) do
              safe_join([
                helpers.app_icon("brush-cleaning", class: "size-3", aria: { hidden: true }),
                tag.span(count)
              ])
            end
          end
          housekeeping_content
        end
      end

      def housekeeping_content
        tag.div(class: "space-y-3 text-left") do
          safe_join([
            tag.div do
              safe_join([
                tag.p("Housekeeping", class: "text-sm font-semibold text-foreground"),
                tag.p("Current active requests", class: "text-xs text-muted-foreground")
              ])
            end,
            tag.ul(class: "max-h-64 space-y-2 overflow-y-auto", aria: { label: "Active housekeeping requests" }) do
              safe_join(@room.housekeeping_alerts.map { |alert| housekeeping_item(alert) })
            end
          ])
        end
      end

      def housekeeping_item(alert)
        tag.li(class: "rounded-md border border-border bg-muted p-2") do
          safe_join([
            tag.p(alert.details, class: "break-words text-sm text-foreground"),
            tag.p(
              [ alert.status.to_s.humanize, alert.assigned_to_name.presence || "Unassigned" ].join(" · "),
              class: "mt-1 text-xs text-muted-foreground"
            ),
            tag.time(
              alert.requested_at.to_fs(:short),
              datetime: alert.requested_at.iso8601,
              class: "mt-1 block text-xs text-muted-foreground"
            )
          ])
        end
      end
    end
  end
end

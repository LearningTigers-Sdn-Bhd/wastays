# frozen_string_literal: true

module HotelPortal
  module StayView
    class OperationalIndicators < PanelsUI::BaseComponent
      PRESENTATIONS = {
        dnd: { label: "Do not disturb", icon: "door-closed", variant: :warning }.freeze,
        priority: { label: "Cleaning priority", icon: "flag", variant: :destructive }.freeze,
        housekeeping: { label: "Housekeeping request", icon: "brush-cleaning", variant: :info }.freeze
      }.freeze

      def initialize(room:, state: nil, class: nil, **attributes)
        @room = room
        @state = state
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
          housekeeping_popover,
          (flag_badge(:priority) if @room.operational_flags[:priority]),
          (flag_badge(:dnd) if @room.operational_flags[:dnd])
        ].compact
      end

      def flag_badge(key)
        presentation = PRESENTATIONS.fetch(key)
        render PanelsUI::Tooltip.new(text: presentation.fetch(:label), id: "#{@room.dom_id}-#{key}-tooltip") do
          render PanelsUI::Badge.new(
            variant: presentation.fetch(:variant),
            size: :sm,
            shape: :circular,
            role: "img",
            tabindex: 0,
            aria: { label: presentation.fetch(:label) }
          ) do
            helpers.app_icon(presentation.fetch(:icon), class: "size-3", aria: { hidden: true })
          end
        end
      end

      def housekeeping_popover
        return if @room.housekeeping_alerts.empty?

        presentation = PRESENTATIONS.fetch(:housekeeping)
        count = @room.housekeeping_alerts.size
        label = helpers.pluralize(count, "active housekeeping request")
        render PanelsUI::Popover.new(
          id: "#{@room.dom_id}-housekeeping",
          placement: :bottom_end,
          class: "w-72 p-3",
          focus: true
        ) do |popover|
          popover.with_trigger(unstyled: true, aria_label: label, class: "inline-flex rounded-full") do
            render PanelsUI::Badge.new(
              variant: presentation.fetch(:variant),
              size: :sm,
              shape: :rounded,
              class: "gap-1",
              aria: { hidden: true }
            ) do
              safe_join([
                helpers.app_icon(presentation.fetch(:icon), class: "size-3", aria: { hidden: true }),
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
            ),
            housekeeping_item_actions(alert)
          ].compact)
        end
      end

      def housekeeping_item_actions(alert)
        return unless @state

        actions = helpers.stay_view_housekeeping_task_actions(alert, @room, @state)
        return if actions.empty?

        tag.div(class: "mt-2 flex flex-wrap gap-1.5") do
          safe_join(actions.map { |action| housekeeping_item_action(action) })
        end
      end

      def housekeeping_item_action(action)
        render PanelsUI::Button.new(href: action.fetch(:href), variant: :secondary, size: :xs, data: action.fetch(:data, {})) do
          safe_join([
            helpers.app_icon(action.fetch(:icon), class: "size-3.5", aria: { hidden: true }),
            tag.span(action.fetch(:label))
          ])
        end
      end
    end
  end
end

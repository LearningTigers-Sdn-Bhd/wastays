# frozen_string_literal: true

module HotelPortal
  module StayView
    class StatusGuide < PanelsUI::BaseComponent
      BOOKING_ENTRIES = [
        { state: :arrival, label: "Arrival", icon: "circle-check", presentation: :segment, tone: :info, emphasis: :solid }.freeze,
        { state: :in_house, label: "In-house", icon: "log-in", presentation: :segment, tone: :success, emphasis: :solid }.freeze,
        { state: :completed, label: "Completed", icon: "check-check", presentation: :segment, tone: :completed, emphasis: :solid }.freeze
      ].freeze

      ROOM_STATUS_ENTRIES = [
        { state: :ready, label: "Ready" },
        { state: :dirty, label: "Dirty" },
        { state: :cleaning, label: "Cleaning" },
        { state: :awaiting_inspection, label: "Awaiting inspection" },
        { state: :inspection_failed, label: "Inspection failed" },
        { state: :out_of_service, label: "Out of service" }
      ].map do |entry|
        entry.merge(
          presentation: :badge,
          icon: RoomSummary::STATUS_ICONS.fetch(entry.fetch(:state)),
          variant: RoomSummary::STATUS_VARIANTS.fetch(entry.fetch(:state))
        ).freeze
      end.freeze

      ROOM_BLOCK_ENTRIES = [
        { state: :maintenance, label: "Maintenance", icon: "wrench" },
        { state: :deep_cleaning, label: "Deep cleaning", icon: "brush-cleaning" },
        { state: :renovation, label: "Renovation", icon: "construction" },
        { state: :owner_use, label: "Owner use", icon: "house" },
        { state: :admin_hold, label: "Admin hold", icon: "key-round" }
      ].map do |entry|
        entry.merge(
          presentation: :segment,
          tone: OperationalBar::KIND_TONES.fetch(entry.fetch(:state)),
          emphasis: :hatched
        ).freeze
      end.freeze

      INDICATOR_ENTRIES = OperationalIndicators::PRESENTATIONS.map do |state, presentation|
        presentation.merge(state:, presentation: :badge).freeze
      end.freeze

      GUEST_STATUS_ENTRIES = [
        { state: :blacklisted, label: "Blacklisted", icon: "ban", presentation: :badge, variant: :destructive }.freeze,
        {
          state: :vip, label: "VIP", icon: "crown-simple", presentation: :badge, variant: :warning,
          library: "phosphor", icon_variant: "duotone"
        }.freeze,
        { state: :repeat, label: "Repeat", icon: "repeat", presentation: :badge, variant: :info }.freeze
      ].freeze

      GROUPS = [
        {
          label: "Booking status",
          entries: BOOKING_ENTRIES
        },
        {
          label: "Current room status",
          entries: ROOM_STATUS_ENTRIES
        },
        {
          label: "Room blocks",
          entries: ROOM_BLOCK_ENTRIES
        },
        {
          label: "Indicators",
          entries: INDICATOR_ENTRIES
        }
      ].freeze
      FINANCIAL_ENTRIES = [
        {
          state: :financial_attention, label: "Financial attention", icon: "circle-dollar-sign",
          presentation: :badge, variant: :warning
        }.freeze,
        {
          state: :direct_bill, label: "Direct Bill", icon: "landmark",
          presentation: :badge, variant: :info
        }.freeze
      ].freeze

      def initialize(view_booking:, view_financial_status:)
        @view_booking = view_booking
        @view_financial_status = view_financial_status
      end

      def call
        render PanelsUI::Popover.new(
          id: "stay-view-status-guide",
          placement: :bottom_end,
          class: "max-h-96 w-80 overflow-y-auto p-3"
        ) do |popover|
          popover.with_trigger(
            variant: :ghost,
            size: :icon_sm,
            aria_label: "Stay View status guide"
          ) do
            helpers.app_icon("info", class: "size-4", aria: { hidden: true })
          end
          content
        end
      end

      private

      def content
        tag.div(class: "space-y-4 text-left") do
          safe_join([
            tag.div do
              safe_join([
                tag.p("Status guide", class: "text-sm font-semibold text-foreground"),
                tag.p("Statuses and indicators used in Stay View.", class: "text-xs text-muted-foreground")
              ])
            end,
            safe_join(groups.map { |group| group_content(group) })
          ])
        end
      end

      def groups
        visible_groups = GROUPS
        visible_groups = [ *visible_groups, { label: "Guest status", entries: GUEST_STATUS_ENTRIES } ] if @view_booking
        visible_groups = [ *visible_groups, { label: "Financial", entries: FINANCIAL_ENTRIES } ] if @view_financial_status

        visible_groups
      end

      def group_content(group)
        tag.section(aria: { label: group.fetch(:label) }) do
          safe_join([
            tag.h3(group.fetch(:label), class: "text-xs font-medium text-muted-foreground"),
            tag.ul(class: "mt-2 grid grid-cols-2 gap-2") do
              safe_join(group.fetch(:entries).map { |entry| entry_content(entry) })
            end
          ])
        end
      end

      def entry_content(entry)
        tag.li(class: "flex min-w-0 items-center gap-2 text-xs text-foreground") do
          safe_join([
            swatch(entry),
            tag.span(entry.fetch(:label), class: "min-w-0")
          ])
        end
      end

      def swatch(entry)
        presentation = entry.fetch(:presentation)
        tag.div(
          class: tw_merge(
            "panel-timeline__legend-swatch",
            ("panel-badge" if presentation == :badge)
          ),
          data: {
            slot: "stay-view-status-swatch",
            state: entry.fetch(:state),
            presentation:,
            tone: entry[:tone],
            emphasis: entry[:emphasis],
            variant: entry[:variant]
          }.compact,
          aria: { hidden: true }
        ) do
          helpers.app_icon(
            entry.fetch(:icon),
            **entry.slice(:library).merge(variant: entry[:icon_variant], class: "size-3", aria: { hidden: true }).compact
          )
        end
      end
    end
  end
end

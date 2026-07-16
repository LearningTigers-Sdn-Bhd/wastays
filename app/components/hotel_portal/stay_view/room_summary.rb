# frozen_string_literal: true

module HotelPortal
  module StayView
    class RoomSummary < PanelsUI::BaseComponent
      STATUS_VARIANTS = {
        ready: :success,
        dirty: :warning,
        cleaning: :info,
        awaiting_inspection: :info,
        inspection_failed: :destructive,
        out_of_service: :destructive
      }.freeze

      def initialize(room:, class: nil, **attributes)
        @room = room
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def before_render
        raise ArgumentError, "RoomSummary requires a StayView::RoomRow" unless @room.is_a?(::StayView::RoomRow)
      end

      def call
        tag.div(**summary_attributes) do
          safe_join([
            tag.div(class: "min-w-0") do
              safe_join([
                tag.p(@room.room_number, class: "truncate text-sm font-semibold text-foreground"),
                tag.p(@room.room_type_name, class: "truncate text-xs text-muted-foreground")
              ])
            end,
            status_badge
          ])
        end
      end

      private

      def summary_attributes
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || attributes.delete("data") || {}

        attributes.merge(
          class: tw_merge("flex h-full min-w-0 items-center justify-between gap-2 px-3 py-2", @class, attributes.delete(:class)),
          data: data.merge(slot: "stay-view-room-summary")
        )
      end

      def status_badge
        status = @room.current_physical_status || :unknown
        render PanelsUI::Badge.new(
          label: status.to_s.humanize,
          variant: STATUS_VARIANTS.fetch(status, :neutral),
          size: :sm,
          indicator: status != :unknown,
          class: "max-w-24 shrink-0"
        )
      end
    end
  end
end

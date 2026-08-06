# frozen_string_literal: true

module HotelPortal
  module StayView
    class RoomBlockItem < PanelsUI::BaseComponent
      def initialize(segment:, state:)
        @segment = segment
        @state = state
      end

      def before_render
        raise ArgumentError, "RoomBlockItem requires a StayView::OperationalSegment" unless @segment.is_a?(::StayView::OperationalSegment)
      end

      def call
        if permitted_href
          helpers.link_to(permitted_href, **item_attributes.merge(data: helpers.stay_view_action_data.merge(slot: "stay-view-room-block-item"))) do
            item_content
          end
        else
          tag.div(item_content, **item_attributes.merge(data: { slot: "stay-view-room-block-item" }))
        end
      end

      private

      def permitted_href
        return unless @segment.capabilities.manage_room_blocks?

        helpers.edit_hotel_stay_view_room_block_path(
          helpers.current_hotel,
          @segment.room_block_id,
          return_to: @state.return_path(helpers.current_hotel),
          source: "stay_view"
        )
      end

      def item_attributes
        {
          class: "group block h-full rounded-md border border-border bg-card p-2.5 text-left outline-none transition-colors hover:border-border-interactive hover:bg-muted focus-visible:border-border-interactive focus-visible:ring-2 focus-visible:ring-ring/30",
          aria: { label: (@segment.capabilities.manage_room_blocks? ? "Manage #{@segment.accessible_label}" : @segment.accessible_label) }
        }
      end

      def item_content
        tag.div(class: "space-y-1.5") do
          safe_join([
            tag.div(class: "flex items-start justify-between gap-2") do
              safe_join([
                tag.div(class: "min-w-0") do
                  safe_join([
                    tag.p(@segment.label, class: "text-sm font-medium text-foreground"),
                    tag.p("Blocked until #{(@segment.end_date - 1.day).to_fs(:medium)}", class: "text-xs text-muted-foreground")
                  ])
                end,
                (helpers.app_icon("chevron-right", class: "mt-0.5 size-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5", aria: { hidden: true }) if permitted_href)
              ].compact)
            end,
            (tag.p(@segment.reason, class: "break-words text-xs text-foreground") if @segment.reason.present?)
          ].compact)
        end
      end
    end
  end
end

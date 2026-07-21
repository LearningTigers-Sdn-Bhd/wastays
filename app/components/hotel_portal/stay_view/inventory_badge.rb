# frozen_string_literal: true

module HotelPortal
  module StayView
    class InventoryBadge < PanelsUI::BaseComponent
      def initialize(summary:, room_type_name:)
        @summary = summary
        @room_type_name = room_type_name.to_s
      end

      def before_render
        return if @summary.is_a?(::StayView::InventoryDateSummary) && @room_type_name.present?

        raise ArgumentError, "InventoryBadge requires an inventory summary and room type name"
      end

      def call
        render PanelsUI::Badge.new(
          label: @summary.available,
          variant: :outline,
          size: :sm,
          shape: :rounded,
          role: "img",
          aria: { label: accessible_label },
          data: { slot: "stay-view-inventory-badge" }
        )
      end

      private

      def accessible_label
        rooms = "room".pluralize(@summary.available)
        "#{@summary.available} available #{rooms} for #{@room_type_name} on #{I18n.l(@summary.date, format: :long)}"
      end
    end
  end
end

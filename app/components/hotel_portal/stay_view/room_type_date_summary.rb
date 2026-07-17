# frozen_string_literal: true

module HotelPortal
  module StayView
    class RoomTypeDateSummary < PanelsUI::BaseComponent
      def initialize(summary:, room_type_name:, view_rates:)
        @summary = summary
        @room_type_name = room_type_name.to_s
        @view_rates = view_rates
      end

      def before_render
        return if @summary.is_a?(::StayView::InventoryDateSummary) && @room_type_name.present?

        raise ArgumentError, "RoomTypeDateSummary requires an inventory summary and room type name"
      end

      def call
        tag.div(class: "flex flex-col items-center justify-center gap-1") do
          safe_join([
            render(InventoryBadge.new(summary: @summary, room_type_name: @room_type_name)),
            (rate_text if @view_rates)
          ].compact)
        end
      end

      private

      def rate_text
        value = if @summary.standard_rate
          CurrencyFormatter.format(
            @summary.standard_rate.amount,
            currency: @summary.standard_rate.currency,
            symbol: false
          )
        else
          "N/A"
        end

        tag.span(
          value,
          class: "panel-timeline__summary-metadata",
          aria: { label: rate_accessible_label(value) },
          data: { slot: "stay-view-standard-rate" }
        )
      end

      def rate_accessible_label(value)
        currency = " #{@summary.standard_rate.currency}" if @summary.standard_rate
        "Standard nightly rate for #{@room_type_name} on #{I18n.l(@summary.date, format: :long)}: #{value}#{currency}"
      end
    end
  end
end

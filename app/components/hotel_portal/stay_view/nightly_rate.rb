# frozen_string_literal: true

module HotelPortal
  module StayView
    class NightlyRate < PanelsUI::BaseComponent
      CONTEXTS = %i[timeline room_card].freeze

      def initialize(summary:, room_type_name:, view_rates:, context: :timeline)
        @summary = summary
        @room_type_name = room_type_name.to_s
        @view_rates = view_rates
        @context = context.to_sym
      end

      def render? = @view_rates

      def before_render
        return if @summary.is_a?(::StayView::InventoryDateSummary) &&
          @room_type_name.present? && @context.in?(CONTEXTS)

        raise ArgumentError, "NightlyRate requires an inventory summary, room type name, and supported context"
      end

      def call
        tag.span(
          content,
          class: context_class,
          aria: { label: accessible_label },
          data: { slot: "stay-view-standard-rate", context: @context }
        )
      end

      private

      def content
        return value if @context == :timeline

        safe_join([
          helpers.app_icon("banknote", class: "size-3.5 shrink-0", aria: { hidden: true }),
          tag.span(room_card_value, class: "font-medium text-foreground")
        ])
      end

      def context_class
        return "panel-timeline__summary-metadata" if @context == :timeline

        "inline-flex items-center gap-1.5 text-xs text-muted-foreground"
      end

      def value
        return "N/A" unless @summary.standard_rate

        CurrencyFormatter.format(
          @summary.standard_rate.amount,
          currency: @summary.standard_rate.currency,
          unit: :none
        )
      end

      def room_card_value
        return value unless @summary.standard_rate

        "#{@summary.standard_rate.currency} #{value}"
      end

      def accessible_label
        currency = " #{@summary.standard_rate.currency}" if @summary.standard_rate
        "Standard nightly rate for #{@room_type_name} on #{I18n.l(@summary.date, format: :long)}: #{value}#{currency}"
      end
    end
  end
end

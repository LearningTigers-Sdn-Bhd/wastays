# frozen_string_literal: true

module HotelPortal
  module StayView
    class TimelineFooterMetric < PanelsUI::BaseComponent
      METRICS = %i[available occupancy].freeze

      def initialize(summary:, metric:)
        @summary = summary
        @metric = metric.to_sym
      end

      def before_render
        unless @summary.is_a?(::StayView::FooterDateSummary)
          raise ArgumentError, "TimelineFooterMetric requires a footer summary"
        end
        return if METRICS.include?(@metric)

        raise ArgumentError, "TimelineFooterMetric metric must be one of: #{METRICS.join(', ')}"
      end

      def call
        @metric == :available ? available_value : occupancy_value
      end

      private

      def available_value
        rooms = "room".pluralize(@summary.available)
        tag.span(
          @summary.available,
          class: "font-semibold tabular-nums",
          aria: { label: "#{@summary.available} available #{rooms} on #{formatted_date}" },
          data: { slot: "stay-view-footer-available" }
        )
      end

      def occupancy_value
        value = @summary.occupancy.nil? ? "N/A" : "#{(@summary.occupancy * 100).round}%"
        label = if @summary.occupancy.nil?
          "Occupancy unavailable on #{formatted_date} because sellable inventory is zero"
        else
          "#{(@summary.occupancy * 100).round} percent occupied on #{formatted_date}"
        end

        tag.span(
          value,
          class: "panel-timeline__summary-metadata tabular-nums",
          aria: { label: },
          data: { slot: "stay-view-footer-occupancy" }
        )
      end

      def formatted_date
        I18n.l(@summary.date, format: :long)
      end
    end
  end
end

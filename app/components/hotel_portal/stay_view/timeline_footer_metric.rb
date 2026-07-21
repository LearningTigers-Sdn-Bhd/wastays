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
        return occupancy_label if @summary.occupancy.nil?

        percent = (@summary.occupancy * 100).round
        tag.div(class: "flex w-full min-w-0 items-center gap-1.5") do
          safe_join([
            render(PanelsUI::Progress.new(value: percent, max: 100, size: :sm, class: "min-w-0 flex-1 border border-border", aria: { hidden: "true" })),
            occupancy_label(percent)
          ])
        end
      end

      def occupancy_label(percent = nil)
        value = percent.nil? ? "N/A" : "#{percent}%"
        label = if percent.nil?
          "Occupancy unavailable on #{formatted_date} because sellable inventory is zero"
        else
          "#{percent} percent occupied on #{formatted_date}"
        end

        tag.span(
          value,
          class: "panel-timeline__summary-metadata tabular-nums shrink-0",
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

# frozen_string_literal: true

module HotelPortal
  module Reports
    class MetricStrip < PanelsUI::BaseComponent
      COLUMN_CLASSES = {
        1 => "grid-cols-1",
        2 => "grid-cols-1 md:grid-cols-2",
        3 => "grid-cols-1 md:grid-cols-2 xl:grid-cols-3",
        4 => "grid-cols-1 md:grid-cols-2 xl:grid-cols-4",
        5 => "grid-cols-1 md:grid-cols-2 xl:grid-cols-5",
        6 => "grid-cols-1 md:grid-cols-2 xl:grid-cols-3"
      }.freeze
      CARD_KEYS = %i[label value detail detail_variant icon].freeze

      def initialize(metrics:, aria_label: "Report summary", class: nil)
        raise ArgumentError, "MetricStrip requires one to six metrics" unless metrics.size.between?(1, 6)
        raise ArgumentError, "MetricStrip requires a supporting description for every metric" if metrics.any? { |metric| metric[:detail].blank? }

        @metrics = metrics
        @aria_label = aria_label
        @class = binding.local_variable_get(:class)
      end

      def call
        tag.section(
          safe_join(@metrics.map { |metric| render_metric(metric) }),
          class: tw_merge(
            "grid gap-px overflow-hidden rounded-lg border border-border bg-border #{COLUMN_CLASSES.fetch(@metrics.size)}",
            @class
          ),
          aria: { label: @aria_label },
          data: { slot: "report-metric-strip" }
        )
      end

      private

      def render_metric(metric)
        render PanelsUI::MetricCard.new(
          **metric.symbolize_keys.slice(*CARD_KEYS),
          density: :compact,
          class: "rounded-none border-0 shadow-none",
          data: { slot: "report-metric" }
        )
      end
    end
  end
end

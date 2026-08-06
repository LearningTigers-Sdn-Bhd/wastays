# frozen_string_literal: true

module StayView
  class CalculateFooterSummaries
    def self.call(room_groups:, dates:)
      dates.map do |date|
        normalized_date = date.to_date
        summaries = room_groups.filter_map { |group| group.inventory_summary_for(normalized_date) }
        sellable = summaries.sum(&:sellable)
        sold = summaries.sum(&:sold)

        FooterDateSummary.new(
          date: normalized_date,
          sellable:,
          sold:,
          available: summaries.sum(&:available),
          occupancy: sellable.zero? ? nil : sold.fdiv(sellable)
        )
      end.freeze
    end
  end
end

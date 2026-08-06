# frozen_string_literal: true

module HotelPortal
  module Reports
    class PayoutsExportResult
      attr_reader :active_tab, :upcoming_rows, :processing_rows, :paid_rows, :paid_start_date, :paid_end_date

      def initialize(active_tab:, upcoming_rows:, processing_rows:, paid_rows:, paid_start_date:, paid_end_date:)
        @active_tab = active_tab.to_s == "paid" ? "paid" : "upcoming"
        @upcoming_rows = normalize_rows(upcoming_rows, %i[booking_reference checked_out_at status net_amount])
        @processing_rows = normalize_rows(processing_rows, %i[period_start period_end status reference net_amount])
        @paid_rows = normalize_rows(paid_rows, %i[period_start period_end settled_at status reference net_amount])
        @paid_start_date = paid_start_date&.to_date
        @paid_end_date = paid_end_date&.to_date
        freeze
      end

      def paid?
        active_tab == "paid"
      end

      def upcoming_total
        upcoming_rows.sum { |row| row[:net_amount] }
      end

      def processing_total
        processing_rows.sum { |row| row[:net_amount] }
      end

      def paid_total
        paid_rows.sum { |row| row[:net_amount] }
      end

      private

      def normalize_rows(rows, keys)
        rows.map do |row|
          keys.index_with do |key|
            value = row.fetch(key)
            key == :net_amount ? value.to_d : value
          end.freeze
        end.freeze
      end
    end
  end
end

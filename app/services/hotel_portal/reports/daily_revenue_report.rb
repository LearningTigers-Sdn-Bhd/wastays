# frozen_string_literal: true

module HotelPortal
  module Reports
    class DailyRevenueReport
      SOURCE_LABELS = {
        "walk_in" => "Walk-in",
        "agoda" => "Agoda",
        "whatsapp" => "WhatsApp",
        "corporate" => "Corporate",
        "internal" => "Direct"
      }.freeze

      Result = Struct.new(:start_date, :end_date, :totals, :rows, :source_rows, keyword_init: true)

      def initialize(hotel:, start_date:, end_date:)
        @hotel = hotel
        @start_date = start_date
        @end_date = end_date
      end

      def call
        bookings = @hotel.bookings.revenue_generating.created_between(@start_date, @end_date)

        rows = bookings.group_by { |booking| booking.created_at.to_date }.sort.map do |date, grouped|
          row_payload(date, grouped)
        end

        source_rows = bookings.group_by { |booking| normalize_source(booking.source) }
                              .map { |source, grouped| row_payload(source, grouped, key: :source) }
                              .sort_by { |row| -row[:total_revenue] }

        room_revenue = bookings.sum(:total_amount).to_d
        tax_amount = bookings.where(tourism_tax_applied: true).sum(:tourism_tax_amount).to_d

        Result.new(
          start_date: @start_date,
          end_date: @end_date,
          totals: {
            booking_count: bookings.count,
            room_revenue: room_revenue,
            tax_amount: tax_amount,
            total_revenue: room_revenue + tax_amount
          },
          rows: rows,
          source_rows: source_rows
        )
      end

      private

      def row_payload(identifier, grouped, key: :date)
        room_revenue = grouped.sum(&:total_amount).to_d
        tax_amount = grouped.sum { |booking| booking.tourism_tax_applied? ? booking.tourism_tax_amount.to_d : 0.to_d }

        {
          key => identifier,
          booking_count: grouped.count,
          room_revenue: room_revenue,
          tax_amount: tax_amount,
          total_revenue: room_revenue + tax_amount
        }
      end

      def normalize_source(source)
        source_key = source.to_s.strip
        source_key = "unknown" if source_key.empty?

        SOURCE_LABELS[source_key] || source_key.titleize.presence || "Others"
      end
    end
  end
end

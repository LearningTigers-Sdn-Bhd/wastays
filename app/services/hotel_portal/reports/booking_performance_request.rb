# frozen_string_literal: true

module HotelPortal
  module Reports
    # Reads the booking performance report out of the request parameters. It
    # holds the visible columns, the grouping, the header filters, the report,
    # and the row selection.
    class BookingPerformanceRequest
      REPORT_KEY = "booking_performance"
      # Each grouping needs its column on screen. The booking date grouping is
      # the default one, so it stays available at all times.
      GROUPING_COLUMNS = {
        "booking_date" => nil,
        "source" => "source",
        "fund_collector" => "fund_collector",
        "status" => "status",
        "currency" => "currency"
      }.freeze

      def initialize(hotel:, user:, params:, start_date:, end_date:, date_preset:)
        @hotel = hotel
        @user = user
        @params = params
        @start_date = start_date
        @end_date = end_date
        @date_preset = date_preset
      end

      def visible_columns
        @visible_columns ||= ReportViewPreferences::Read.new(
          hotel: @hotel, user: @user, report_key: REPORT_KEY, columns: BookingPerformanceColumns
        ).visible_columns
      end

      def group_by
        @group_by ||= begin
          requested = @params[:group_by].presence_in(BookingPerformanceReport::GROUPINGS)
          grouping = requested || BookingPerformanceReport::DEFAULT_GROUPING
          column = GROUPING_COLUMNS.fetch(grouping)
          column.nil? || visible_columns.include?(column) ? grouping : BookingPerformanceReport::DEFAULT_GROUPING
        end
      end

      def filters
        @filters ||= {
          booking_sources: filter_values(:booking_sources),
          fund_collectors: fund_collector_values,
          statuses: filter_values(:statuses),
          payment_statuses: filter_values(:payment_statuses),
          currencies: filter_values(:currencies)
        }
      end

      def report
        @report ||= BookingPerformanceReport.new(
          hotel: @hotel,
          bookings: Booking.for_financial_breakdown(@hotel, @start_date, @end_date, @params[:q]),
          group_by:,
          date_preset: @date_preset,
          filters:,
          start_date: @start_date,
          end_date: @end_date
        )
      end

      def selection
        @selection ||= BookingPerformanceSelection.new(
          report:,
          group_by: @params[:selection_group_by] || group_by,
          booking_ids: @params[:selected_booking_ids],
          group_values: @params[:selected_booking_groups],
          excluded_booking_ids: @params[:excluded_booking_ids]
        )
      end

      # The report that an export writes: the whole filtered scope, or only the
      # rows that the user selected.
      def export_report
        return report unless selection.selected?

        report.subset(selection.selected_ids)
      end

      private

      def filter_values(key)
        return unless @params.key?(key)

        values = Array(@params[key]).map(&:to_s)
        return [] if values.include?("__none__")

        values.reject { |value| value == "__all__" }
      end

      def fund_collector_values
        return filter_values(:fund_collectors) if @params.key?(:fund_collectors)
        return [ @params[:fund_collector].to_s ] if @params[:fund_collector].present?

        nil
      end
    end
  end
end

# frozen_string_literal: true

module HotelPortal
  class BookingPerformanceViewPreferencesController < HotelPortal::ReportViewPreferencesController
    self.report_key = "booking_performance"
    self.report_columns = HotelPortal::Reports::BookingPerformanceColumns
  end
end

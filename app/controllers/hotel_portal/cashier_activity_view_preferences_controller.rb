# frozen_string_literal: true

module HotelPortal
  class CashierActivityViewPreferencesController < HotelPortal::ReportViewPreferencesController
    self.report_key = "daily_report_cashier_activity"
    self.report_columns = HotelPortal::Reports::CashierActivityColumns
  end
end

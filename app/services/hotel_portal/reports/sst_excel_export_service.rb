# frozen_string_literal: true

module HotelPortal
  module Reports
    class SstExcelExportService < TaxComplianceExcelExportService
      def initialize(hotel:, report:) = super(hotel: hotel, report: report, type: :sst)
    end
  end
end

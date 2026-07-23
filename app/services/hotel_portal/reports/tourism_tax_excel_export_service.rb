# frozen_string_literal: true

module HotelPortal
  module Reports
    class TourismTaxExcelExportService < TaxComplianceExcelExportService
      def initialize(hotel:, report:) = super(hotel: hotel, report: report, type: :tourism_tax)
    end
  end
end

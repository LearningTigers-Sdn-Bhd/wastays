# frozen_string_literal: true

module HotelPortal
  module Reports
    class TourismTaxPdfExportService < TaxCompliancePdfExportService
      def initialize(hotel:, report:) = super(hotel: hotel, report: report, type: :tourism_tax)
    end
  end
end

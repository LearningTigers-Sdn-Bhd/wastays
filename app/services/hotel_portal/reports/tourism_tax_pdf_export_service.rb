# frozen_string_literal: true

module HotelPortal
  module Reports
    class TourismTaxPdfExportService < TaxCompliancePdfExportService
      def initialize(hotel:, report:, prepared_by:) = super(hotel: hotel, report: report, type: :tourism_tax, prepared_by: prepared_by)
    end
  end
end

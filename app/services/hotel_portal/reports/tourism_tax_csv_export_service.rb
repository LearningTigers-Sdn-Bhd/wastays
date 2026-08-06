# frozen_string_literal: true

module HotelPortal
  module Reports
    class TourismTaxCsvExportService < TaxComplianceCsvExportService
      def initialize(report:) = super(report: report, type: :tourism_tax)
    end
  end
end

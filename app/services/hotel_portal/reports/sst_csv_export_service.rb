# frozen_string_literal: true

module HotelPortal
  module Reports
    class SstCsvExportService < TaxComplianceCsvExportService
      def initialize(report:) = super(report: report, type: :sst)
    end
  end
end

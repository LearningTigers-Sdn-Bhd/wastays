# frozen_string_literal: true

module HotelPortal
  module Reports
    class NonNationalCsvExportService < TaxComplianceCsvExportService
      def initialize(report:) = super(report: report, type: :non_national)
    end
  end
end

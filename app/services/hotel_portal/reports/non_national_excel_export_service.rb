# frozen_string_literal: true

module HotelPortal
  module Reports
    class NonNationalExcelExportService < TaxComplianceExcelExportService
      def initialize(hotel:, report:) = super(hotel: hotel, report: report, type: :non_national)
    end
  end
end

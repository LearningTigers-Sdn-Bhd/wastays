# frozen_string_literal: true

module HotelPortal
  module Reports
    class NonNationalPdfExportService < TaxCompliancePdfExportService
      def initialize(hotel:, report:, prepared_by:) = super(hotel: hotel, report: report, type: :non_national, prepared_by: prepared_by)
    end
  end
end

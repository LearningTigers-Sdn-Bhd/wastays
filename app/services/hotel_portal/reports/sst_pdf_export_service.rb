# frozen_string_literal: true

module HotelPortal
  module Reports
    class SstPdfExportService < TaxCompliancePdfExportService
      def initialize(hotel:, report:, prepared_by:) = super(hotel: hotel, report: report, type: :sst, prepared_by: prepared_by)
    end
  end
end

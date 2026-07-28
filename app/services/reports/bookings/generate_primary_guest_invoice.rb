# frozen_string_literal: true

module Reports
  module Bookings
    class GeneratePrimaryGuestInvoice
      def initialize(booking:, printed_by: nil)
        @booking = booking
        @printed_by = printed_by
      end

      def generate
        Reports::Bookings::GenerateInvoice.new(folio: guest_folio, printed_by: @printed_by).generate
      end

      private

      def guest_folio
        folios = @booking.booking_folios.includes(:invoice).to_a
        folio = folios.find { |candidate| candidate.id == @booking.booking_folio&.id && guest_invoice?(candidate) }
        folio ||= folios.find { |candidate| candidate.is_primary? && guest_invoice?(candidate) }
        folio ||= folios.find { |candidate| guest_invoice?(candidate) }
        return folio if folio.present?

        raise Reports::Bookings::GenerateFolioRecords::UnavailableError,
          "No finalized guest folio invoice is available for this booking."
      end

      def guest_invoice?(folio)
        folio.payer_type == "guest" &&
          folio.closed? &&
          folio.invoice&.kind_settled? &&
          folio.invoice&.finalized?
      end
    end
  end
end

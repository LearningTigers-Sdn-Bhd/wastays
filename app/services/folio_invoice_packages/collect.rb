# frozen_string_literal: true

module FolioInvoicePackages
  class Collect
    def self.call(hotel:, bookings:)
      new(hotel:, bookings:).call
    end

    def initialize(hotel:, bookings:)
      @hotel = hotel
      @booking_ids = Array(bookings).map { |booking| booking.respond_to?(:id) ? booking.id : booking }.compact.uniq
    end

    def call
      return [] if @booking_ids.empty?

      @hotel.folio_invoices
        .joins(:booking_folio)
        .where(state: "finalized", booking_folios: { booking_id: @booking_ids, status: "closed" })
        .includes(
          :revisions,
          booking_folio: [
            :ar_invoice,
            :booking_room,
            { booking: [ :booking_rooms, { booking_guests: :guest } ] },
            { booking_billing_party: [ { booking_guest: :guest }, { hotel_corporate_account: { corporate_account: :users } } ] },
            { hotel_corporate_account: { corporate_account: :users } }
          ]
        )
        .order("booking_folios.booking_id", "booking_folios.folio_sequence", :id)
        .select { |invoice| eligible?(invoice) }
    end

    private

    def eligible?(invoice)
      invoice.current_revision.present? && invoice.booking_folio.ar_invoice.blank?
    end
  end
end

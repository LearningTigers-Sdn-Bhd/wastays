# frozen_string_literal: true

module Folios
  class DestinationPolicy
    def self.bookings(booking:)
      scope = booking.hotel.bookings
      booking.group_booking_id.present? ? scope.where(group_booking_id: booking.group_booking_id) : scope.where(id: booking.id)
    end

    def self.folios(booking:)
      booking.hotel.booking_folios.where(booking_id: bookings(booking:).select(:id), currency: booking.currency)
        .includes(:booking_room, :booking_billing_party, { hotel_corporate_account: :corporate_account }, booking: :booking_rooms).order(:booking_id, :folio_sequence, :id)
    end

    def self.related?(source, target)
      source.present? && target.present? && source.hotel_id == target.hotel_id &&
        (source.id == target.id || (source.group_booking_id.present? && source.group_booking_id == target.group_booking_id))
    end

    def self.error(booking:, folio:, allow_closed: false)
      return "Selected folio is not available." if folio.blank?
      return "Source and target folios must belong to the same hotel." unless folio.hotel_id == booking.hotel_id
      return "Source and target folios must belong to the same booking or group." unless related?(booking, folio.booking)
      return "Source and target folios must use the same currency." unless folio.currency == booking.currency
      return "Target folio must be open." unless folio.open? || (allow_closed && folio.closed?)
      return "AR folios must use the AR correction workflow." if folio.receivable_history.exists? || folio.ar_invoice_corrections.unresolved.exists?

      nil
    end

    def self.label(folio)
      room = folio.booking_room || folio.booking.booking_rooms.first
      [ folio.booking.formatted_reservation_number, ("Room #{room.room_number}" if room&.room_number.present?),
        folio.label.presence, folio.folio_reference_display, folio.payer_display_label ].compact_blank.join(" · ")
    end
  end
end

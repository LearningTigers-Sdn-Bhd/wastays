# frozen_string_literal: true

module Folios
  module Lifecycle
    class IncomingRouteBlocker
      def self.call(folio:)
        routes = FolioRoutingRule.active.where(target_folio_id: folio.id).where.not(booking_id: folio.booking_id)
          .joins(:booking).where.not(bookings: { status: %w[completed cancelled no_show voided] })
          .includes(:transaction_code, booking: :booking_rooms)
        routes = routes.select do |rule|
          Bookings::ScheduledStay.local_date(hotel: folio.hotel, value: rule.booking.check_out) > folio.hotel.current_business_date
        end
        return if routes.empty?

        details = routes.map { |rule| "#{rule.booking.formatted_reservation_number} (Room #{rule.booking.booking_rooms.first&.room_number || "unassigned"}): #{rule.transaction_code.code}" }.uniq.join(", ")
        "Cannot close this folio while group rooms route future charges to it. Change these routes first: #{details}."
      end
    end
  end
end

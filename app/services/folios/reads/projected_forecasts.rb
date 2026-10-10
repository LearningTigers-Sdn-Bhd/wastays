# frozen_string_literal: true

module Folios
  module Reads
    class ProjectedForecasts
      def self.call(folio:)
        scope = folio.folio_forecasted_charges.forecast
        return scope.none if folio.closed? || folio.booking.blank?

        bookings = Booking.where(id: scope.select(:source_booking_id)).where.not(status: %w[cancelled completed no_show voided])
        table = FolioForecastedCharge.arel_table
        predicates = bookings.map do |booking|
          cutoff = Bookings::ScheduledStay.local_date(hotel: folio.hotel, value: booking.check_out)
          table[:source_booking_id].eq(booking.id).and(
            table[:charge_kind].in(%w[extra_charge extra_charge_tax]).or(table[:stay_date].lt(cutoff))
          )
        end
        return scope.none if predicates.empty?

        scope.where(predicates.reduce(&:or)).order(:stay_date, :charge_kind, :identity)
      end
    end
  end
end

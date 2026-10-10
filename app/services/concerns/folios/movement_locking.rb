# frozen_string_literal: true

module Folios
  module MovementLocking
    private

    def lock_movement!(folios:, transactions:)
      # Serialize group financial operations before taking deposit and folio locks.
      booking = folios.first.booking
      booking.group_booking&.lock!
      bookings = Folios::DestinationPolicy.bookings(booking: booking).or(Booking.where(id: folios.map(&:booking_id)))
      bookings.order(:id).lock.load
      deposit_ids = transactions.filter_map { |row| row.metadata["deposit_id"] }.uniq
      Deposit.where(id: deposit_ids).order(:id).lock.load
      folios.compact.uniq(&:id).sort_by(&:id).each(&:lock!)
      transactions.uniq(&:id).sort_by(&:id).each(&:lock!)
    end
  end
end

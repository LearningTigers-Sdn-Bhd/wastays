# frozen_string_literal: true

module StayView
  class ResolveOccupancy
    def self.call(date:, bookings:)
      entries = bookings.filter_map do |booking|
        state = state_for(date.to_date, booking)
        next unless state

        Occupancy.new(
          state: state,
          booking_id: booking.booking_id,
          booking_status: booking.status,
          label: state.to_s.humanize
        )
      end

      entries = [ Occupancy.new(state: :available, label: "Available") ] if entries.empty?
      Immutable.array(entries)
    end

    def self.state_for(date, booking)
      return :arrival if booking.check_in == date
      return :departure if booking.check_out == date
      return :occupied if booking.check_in < date && date < booking.check_out

      nil
    end

    private_class_method :state_for
  end
end

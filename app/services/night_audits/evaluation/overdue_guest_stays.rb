# frozen_string_literal: true

module NightAudits
  module Evaluation
    class OverdueGuestStays
      def initialize(context:)
        @context = context
        @hotel = context.hotel
        @business_date = context.business_date
        @zone = @hotel.hotel_time_zone
      end

      def due_outs
        cutoff = (@business_date + 1.day).in_time_zone(@zone).beginning_of_day
        @context.hotel_bookings
          .where(status: %w[checked_in due_out_detected checkout_required])
          .where("check_out < ?", cutoff)
          .includes(:booking_rooms)
      end

      def missed_arrivals
        detected = @context.hotel_bookings
          .where(status: "no_show_detected")
          .where("no_show_detected_business_date <= ?", @business_date)
          .includes(:booking_rooms, :pre_checkin)

        (confirmed_missed_arrivals.to_a + detected.to_a).uniq(&:id)
      end

      def confirmed_missed_arrivals
        return [] unless @hotel.can_audit_date?(@business_date)

        @context.hotel_bookings.confirmed
          .includes(:booking_rooms, :pre_checkin)
          .checking_in_on(@business_date, @zone)
          .select { |booking| confirmed_missed_arrival?(booking) }
      end

      def confirmed_missed_arrival?(booking)
        booking.status == "confirmed" &&
          Bookings::ScheduledStay.local_date(hotel: @hotel, value: booking.check_in) == @business_date &&
          !active_precheckin_hold?(booking)
      end

      private

      def active_precheckin_hold?(booking)
        precheckin = booking.pre_checkin
        return false unless precheckin&.completed?

        arrival = declared_arrival_at(booking, precheckin)
        arrival && Time.current.in_time_zone(@zone) < arrival + @hotel.arrival_grace_period.seconds
      end

      def declared_arrival_at(booking, precheckin)
        value = precheckin.metadata&.fetch("estimated_arrival_time", nil).presence
        return unless value

        hour, minute = value.to_s.split(":").first(2).map(&:to_i)
        return unless hour&.between?(0, 23) && minute&.between?(0, 59)

        date = Bookings::ScheduledStay.local_date(hotel: @hotel, value: booking.check_in)
        if @hotel.business_ends_at <= @hotel.business_starts_at &&
            (hour * 3600) + (minute * 60) <= (@hotel.business_ends_at.hour * 3600) + (@hotel.business_ends_at.min * 60)
          date += 1.day
        end
        @zone.local(date.year, date.month, date.day, hour, minute)
      end
    end
  end
end

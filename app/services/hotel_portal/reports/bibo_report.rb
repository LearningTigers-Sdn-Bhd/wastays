# frozen_string_literal: true

module HotelPortal
  module Reports
    class BiboReport
      # Each direction is one section, carrying only the date and time of its own
      # leg. Shared by the on-screen tables and the PDF export so both match.
      LEGS = [
        { title: "Boat-ins", rows_key: :boat_ins, date_header: "Arrival Date", date_key: :arrival_date,
          time_header: "Arrival Time", empty_message: "No boat-in records found for this selected period." },
        { title: "Boat-outs", rows_key: :boat_outs, date_header: "Departure Date", date_key: :departure_date,
          time_header: "Departure Time", empty_message: "No boat-out records found for this selected period." }
      ].freeze

      LEG_KEYS = LEGS.map { |leg| leg[:rows_key].to_s }.freeze

      Result = Struct.new(
        :start_date,
        :end_date,
        :boat_ins,
        :boat_outs,
        :boat_in_count,
        :boat_out_count,
        :leg,
        keyword_init: true
      ) do
        # Both directions are already loaded, so narrowing to one leg tab is an
        # in-memory filter rather than another pass at the database.
        def for_leg(leg)
          return self if leg.blank?

          key = leg.to_s
          ins = key == "boat_ins" ? boat_ins : []
          outs = key == "boat_outs" ? boat_outs : []

          Result.new(
            start_date: start_date,
            end_date: end_date,
            boat_ins: ins,
            boat_outs: outs,
            boat_in_count: ins.size,
            boat_out_count: outs.size,
            leg: key
          )
        end

        def count_for(leg)
          leg.to_s == "boat_ins" ? boat_in_count : boat_out_count
        end

        def total_count = boat_in_count + boat_out_count

        # One section per direction being shown: the "all" tab shows both, a leg
        # tab shows its own. Screen tables and PDF pages lay out from these.
        def sections
          LEGS.select { |section| leg.blank? || section[:rows_key].to_s == leg }
              .map { |section| section.merge(rows: public_send(section[:rows_key])) }
        end
      end

      def initialize(hotel:, start_date:, end_date:, leg: nil)
        @hotel = hotel
        @start_date = start_date.to_date
        @end_date = end_date.to_date
        @leg = leg.presence
      end

      def call
        @leg ? full_result.for_leg(@leg) : full_result
      end

      private

      def full_result
        @full_result ||= Result.new(
          start_date: @start_date,
          end_date: @end_date,
          boat_ins: boat_ins,
          boat_outs: boat_outs,
          boat_in_count: boat_ins.size,
          boat_out_count: boat_outs.size,
          leg: nil
        )
      end

      def boat_ins
        @boat_ins ||= booking_guests_scope
          .where(boat_in_at: window)
          .order("booking_guests.boat_in_at ASC, booking_guests.id ASC")
          .map { |bg| row_for(bg, bg.boat_in_at) }
      end

      def boat_outs
        @boat_outs ||= booking_guests_scope
          .where(boat_out_at: window)
          .order("booking_guests.boat_out_at ASC, booking_guests.id ASC")
          .map { |bg| row_for(bg, bg.boat_out_at) }
      end

      def window
        ::Boats::Schedule.day_range(hotel: @hotel, from: @start_date, to: @end_date)
      end

      def booking_guests_scope
        BookingGuest.joins(:booking)
                    .where(bookings: { hotel_id: @hotel.id })
                    .includes(booking: { booking_rooms: :room_type }, guest: {})
      end

      # The two directions differ only in which timestamp they carry.
      def row_for(bg, boat_at)
        booking = bg.booking
        {
          booking_guest_id: bg.id,
          guest_name: bg.name_snapshot || bg.guest.name,
          room_type: booking.booking_rooms.map { |br| br.room_type&.name }.compact.uniq.join(", ").presence || "—",
          room_number: booking.booking_rooms.map(&:room_number).compact.join(", ").presence || "—",
          check_in: booking.check_in,
          check_out: booking.check_out,
          arrival_date: booking.check_in.strftime("%d %b %Y"),
          departure_date: booking.check_out.strftime("%d %b %Y"),
          stay_dates: "#{booking.check_in.strftime('%d %b %Y')} - #{booking.check_out.strftime('%d %b %Y')}",
          confirmation_token: booking.confirmation_token,
          boat_time: format_boat_time(boat_at),
          boat_at: boat_at
        }
      end

      def format_boat_time(value)
        return "—" if value.blank?

        value.in_time_zone(@hotel.hotel_time_zone).strftime("%I:%M %p")
      end
    end
  end
end

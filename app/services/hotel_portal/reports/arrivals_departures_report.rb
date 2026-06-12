# frozen_string_literal: true

module HotelPortal
  module Reports
    class ArrivalsDeparturesReport
      Result = Struct.new(:start_date, :end_date, :arrivals, :departures, :arrival_count, :departure_count, keyword_init: true)

      ARRIVAL_STATUSES = %w[confirmed checked_in].freeze
      DEPARTURE_STATUSES = %w[confirmed checked_in completed].freeze

      def initialize(hotel:, start_date:, end_date:)
        @hotel = hotel
        @start_date = start_date.to_date
        @end_date = end_date.to_date
      end

      def call
        arrivals = arrival_scope.map { |booking| row_for(booking).merge(arrival_fields(booking)) }
        departures = departure_scope.map { |booking| row_for(booking).merge(departure_fields(booking)) }

        Result.new(
          start_date: @start_date,
          end_date: @end_date,
          arrivals: arrivals,
          departures: departures,
          arrival_count: arrivals.size,
          departure_count: departures.size
        )
      end

      private

      def arrival_scope
        @hotel.bookings
              .where(status: ARRIVAL_STATUSES)
              .checking_in_between(@start_date, @end_date, @hotel.hotel_time_zone)
              .includes(:pre_checkin, :booking_notes, booking_rooms: :room_type)
              .order(:check_in, :created_at, :id)
      end

      def departure_scope
        @hotel.bookings
              .where(status: DEPARTURE_STATUSES)
              .checking_out_between(@start_date, @end_date, @hotel.hotel_time_zone)
              .includes(:booking_notes, booking_rooms: :room_type)
              .order(:check_out, :created_at, :id)
      end

      def row_for(booking)
        {
          booking_id: booking.id,
          guest_name: booking.guest_name,
          confirmation_token: booking.confirmation_token,
          status: booking.status,
          check_in: booking.check_in,
          check_out: booking.check_out,
          stay_dates: stay_dates(booking),
          guest_count: guest_count(booking),
          room_details: room_details(booking),
          room_numbers: room_numbers(booking),
          latest_note: latest_note(booking)
        }
      end

      def arrival_fields(booking)
        guarantee = booking.guarantee_method.presence || "none"
        deposit = booking.deposit_status.presence || "not_required"

        {
          pre_checkin_status: booking.pre_checkin_display_status.to_s.humanize,
          guarantee_method_status: guarantee.humanize,
          deposit_status: deposit.humanize,
          guarantee_status: "#{guarantee.humanize} / #{deposit.humanize}"
        }
      end

      def departure_fields(booking)
        {
          departure_status: departure_status(booking)
        }
      end

      def stay_dates(booking)
        "#{booking.check_in.strftime('%d %b %Y')} - #{booking.check_out.strftime('%d %b %Y')}"
      end

      def guest_count(booking)
        parts = []
        parts << ActionController::Base.helpers.pluralize(booking.adults.to_i, "adult")
        parts << ActionController::Base.helpers.pluralize(booking.children.to_i, "child") if booking.children.to_i.positive?
        parts.join(", ")
      end

      def room_details(booking)
        details = booking.booking_rooms.map do |room|
          snapshot_name = room.room_type_snapshot.is_a?(Hash) ? room.room_type_snapshot["name"].presence : nil
          room_name = snapshot_name || room.room_type&.name || "Room"
          "#{room.quantity}x #{room_name}"
        end

        details.presence&.join(", ") || "No rooms assigned"
      end

      def room_numbers(booking)
        numbers = booking.booking_rooms.map { |room| room.room_number.presence || "TBA" }
        numbers.presence&.join(", ") || "TBA"
      end

      def latest_note(booking)
        booking.booking_notes.max_by(&:created_at)&.body.to_s
      end

      def departure_status(booking)
        return "Checked out #{booking.checked_out_at.strftime('%I:%M %p')}" if booking.status == "completed" && booking.checked_out_at.present?

        "Due out"
      end
    end
  end
end

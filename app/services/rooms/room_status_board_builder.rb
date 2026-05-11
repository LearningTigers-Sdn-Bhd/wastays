# frozen_string_literal: true

module Rooms
  class RoomStatusBoardBuilder
    def initialize(hotel:, start_date:, days: 14)
      @hotel = hotel
      @start_date = start_date
      @days = days.to_i
    end

    def call
      groups = room_groups
      {
        dates: dates,
        room_groups: groups,
        status_counts: calculate_status_counts(groups)
      }
    end

    private

    def calculate_status_counts(groups)
      counts = Hash.new(0)
      groups.each do |group|
        group[:rooms].each do |room|
          status = room.dig(:status, :status).to_s
          counts[status] += 1
          counts["all"] += 1
        end
      end
      counts
    end

    def dates
      @dates ||= (@start_date...(@start_date + @days.days)).to_a
    end

    def room_groups
      @hotel.room_types.order(:name).map do |room_type|
        {
          room_type: room_type,
          rooms: room_type.room_numbers.map { |room_number| room_row(room_type, room_number) }
        }
      end
    end

    def room_row(room_type, room_number)
      {
        room_type: room_type,
        room_number: room_number,
        status: status_for(room_type, room_number),
        blocks: booking_blocks_for(room_type, room_number)
      }
    end

    def status_for(room_type, room_number)
      resolved = Rooms::StatusResolver.new(hotel: @hotel, room_type: room_type, room_number: room_number, date: Date.current).call
      {
        status: resolved.status,
        assignable: resolved.assignable,
        room_status_id: resolved.room_status&.id
      }
    end

    def booking_blocks_for(room_type, room_number)
      bookings_for(room_type, room_number).map do |booking|
        {
          id: booking.id,
          guest_name: booking.guest_name,
          status: booking.status,
          check_in: booking.check_in,
          check_out: booking.check_out,
          start_offset: [ (booking.check_in - @start_date).to_i, 0 ].max,
          span: [ ([ booking.check_out + 1.day, dates.last + 1.day ].min - [ booking.check_in, @start_date ].max).to_i, 1 ].max
        }
      end
    end

    def bookings_for(room_type, room_number)
      @hotel.bookings
        .where(status: %w[confirmed checked_in completed])
        .joins(:booking_rooms)
        .where("bookings.check_in < ? AND bookings.check_out > ?", dates.last + 1.day, @start_date)
        .where(booking_rooms: { room_type_id: room_type.id, room_number: room_number })
        .distinct
        .order(:check_in, :id)
    end
  end
end

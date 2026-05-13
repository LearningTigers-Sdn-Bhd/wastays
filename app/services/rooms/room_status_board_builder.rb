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
      @all_bookings = bookings_scope.to_a
      @all_blocks = blocks_scope.to_a
      
      @hotel.room_types.order(:name).map do |room_type|
        {
          room_type: room_type,
          rooms: room_type.room_numbers.map { |room_number| room_row(room_type, room_number) }
        }
      end
    end

    def room_row(room_type, room_number)
      room_bookings = @all_bookings.select do |b| 
        b.booking_rooms.any? { |br| br.room_type_id == room_type.id && br.room_number == room_number }
      end

      room_blocks = @all_blocks.select do |b|
        b.room_type_id == room_type.id && b.room_number == room_number
      end

      {
        room_type: room_type,
        room_number: room_number,
        status: status_for(room_type, room_number, Date.current, room_bookings, room_blocks),
        daily_data: dates.each_with_object({}) do |date, hash|
          hash[date] = status_for(room_type, room_number, date, room_bookings, room_blocks)
        end,
        blocks: booking_blocks_for(room_type, room_number, room_bookings),
        maintenance_blocks: maintenance_blocks_for(room_type, room_number, room_blocks)
      }
    end

    def status_for(room_type, room_number, date, room_bookings, room_blocks = [])
      resolved = Rooms::StatusResolver.new(
        hotel: @hotel, 
        room_type: room_type, 
        room_number: room_number, 
        date: date,
        bookings_scope: room_bookings,
        blocks_scope: room_blocks
      ).call

      {
        status: resolved.status,
        assignable: resolved.assignable,
        room_status_id: resolved.room_status&.id,
        notes: resolved.room_status&.notes,
        booking_state: resolved.booking_state,
        booking_details: resolved.booking_details
      }
    end

    def booking_blocks_for(room_type, room_number, room_bookings)
      room_bookings.map do |booking|
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

    def maintenance_blocks_for(room_type, room_number, room_blocks)
      room_blocks.map do |block|
        {
          id: block.id,
          reason: block.reason,
          block_type: block.block_type,
          start_date: block.start_date,
          end_date: block.end_date,
          start_offset: [ (block.start_date - @start_date).to_i, 0 ].max,
          span: [ ([ block.end_date + 1.day, dates.last + 1.day ].min - [ block.start_date, @start_date ].max).to_i, 1 ].max
        }
      end
    end

    def blocks_scope
      @hotel.room_blocks
        .where(completed_at: nil)
        .for_date_range(@start_date, dates.last)
    end

    def bookings_scope
      @hotel.bookings
        .includes(:booking_rooms)
        .where(status: %w[confirmed checked_in completed])
        .joins(:booking_rooms)
        .where("bookings.check_in < ? AND bookings.check_out > ?", dates.last + 1.day, @start_date)
        .distinct
        .order(:check_in, :id)
    end
  end
end

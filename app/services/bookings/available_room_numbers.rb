# frozen_string_literal: true

module Bookings
  class AvailableRoomNumbers
    def initialize(hotel:, room_type:, check_in:, check_out:, exclude_booking_id: nil)
      @hotel = hotel
      @room_type = room_type
      @check_in = check_in
      @check_out = check_out
      @exclude_booking_id = exclude_booking_id
    end

    def call
      return [] unless @room_type

      availability_snapshot[:available_rooms]
    end

    def options
      return [] unless @room_type

      snapshot = availability_snapshot
      snapshot[:all_rooms].map do |room_number|
        selectable = snapshot[:available_rooms].include?(room_number)
        status = room_status_label(room_number)
        reason = option_unavailable_reason(snapshot, room_number, status)

        {
          room_number: room_number,
          selectable: selectable,
          status: status,
          label: selectable ? room_number : "#{room_number} (#{reason})"
        }
      end
    end

    private

    def availability_snapshot
      return @availability_snapshot if defined?(@availability_snapshot)

      # 1. Get room numbers allowed by inventory for these dates
      inventory_allowed_rooms = (@check_in.to_date..(@check_out.to_date - 1.day)).map do |date|
        inv = @room_type.room_inventories.find_by(date: date)
        if inv
          if inv.status == "open"
            # Legacy quantity mode stores open inventory with an empty available_room_numbers array.
            # In that case, treat all room_type numbers as candidates and let occupancy/locks/status
            # filters decide final assignability.
            inv.available_room_numbers.presence || @room_type.room_numbers
          else
            []
          end
        else
          @room_type.room_numbers
        end
      end

      # Intersection of all days (must be available every day of stay)
      allowed_rooms = inventory_allowed_rooms.reduce(:&) || []

      # 2. Find room numbers already occupied for these dates by other bookings
      occupied = @hotel.bookings.where(status: [ "confirmed", "review_no_show", "checked_in" ])
      occupied = occupied.where.not(id: @exclude_booking_id) if @exclude_booking_id

      occupied_numbers = occupied.where("check_in < ? AND check_out > ?", @check_out, @check_in)
                                 .joins(:booking_rooms)
                                 .where(booking_rooms: { room_type_id: @room_type.id })
                                 .pluck("booking_rooms.room_number")
                                 .compact
                                 .map(&:to_s)
                                 .uniq

      # 3. Find rooms currently locked by other staff members
      locked_numbers = @hotel.room_locks.active
                             .where(room_type_id: @room_type.id)
                             .where.not(user_id: Current.user_id)
                             .pluck(:room_number)

      # 4. Filter them out
      candidate_rooms = (allowed_rooms - occupied_numbers - locked_numbers).reject(&:blank?).map(&:to_s)
      available_rooms = candidate_rooms.select { |room_number| room_selectable_by_status?(room_number) }

      @availability_snapshot = {
        all_rooms: @room_type.room_numbers.map(&:to_s).reject(&:blank?),
        available_rooms: available_rooms,
        allowed_rooms: allowed_rooms.map(&:to_s),
        occupied_numbers: occupied_numbers,
        locked_numbers: locked_numbers.map(&:to_s)
      }
    end

    def room_status_label(room_number)
      room_status = RoomStatus.find_by(hotel: @hotel, room_type: @room_type, room_number: room_number.to_s)
      room_status&.status.presence || "ready"
    end

    def room_selectable_by_status?(room_number)
      status = room_status_label(room_number)
      RoomStatus::ASSIGNABLE_STATUSES.include?(status)
    end

    def option_unavailable_reason(snapshot, room_number, status)
      return status.humanize.titleize unless RoomStatus::ASSIGNABLE_STATUSES.include?(status)
      return "Occupied" if snapshot[:occupied_numbers].include?(room_number)
      return "Locked by another staff" if snapshot[:locked_numbers].include?(room_number)
      return "Unavailable for selected dates" unless snapshot[:allowed_rooms].include?(room_number)

      "Unavailable"
    end
  end
end

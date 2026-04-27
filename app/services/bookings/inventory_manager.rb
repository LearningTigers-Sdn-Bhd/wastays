# frozen_string_literal: true

module Bookings
  class InventoryManager
    def initialize(booking)
      @booking = booking
    end

    def deduct
      @booking.booking_rooms.each do |room|
        update_inventory(room, -room.quantity)
      end
    end

    def release
      @booking.booking_rooms.each do |room|
        update_inventory(room, room.quantity)
      end
    end

    def release_by_dates(start_date, end_date)
      @booking.booking_rooms.each do |room|
        update_inventory(room, room.quantity, dates: (start_date...end_date).to_a)
      end
    end

    private

    def update_inventory(room, quantity_change, dates: nil)
      room_type = room.room_type
      stay_dates = dates || (@booking.check_in...@booking.check_out).to_a

      stay_dates.each do |date|
        inventory = room_type.room_inventories.find_or_initialize_by(date: date)
        if inventory.new_record?
          inventory.quantity = room_type.quantity
          inventory.status = "open"
        end
        new_quantity = [ 0, inventory.quantity + quantity_change ].max
        inventory.update!(quantity: new_quantity)
      end
    end
  end
end

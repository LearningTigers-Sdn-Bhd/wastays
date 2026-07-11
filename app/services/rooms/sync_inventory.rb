# frozen_string_literal: true

module Rooms
  class SyncInventory
    def initialize(hotel:, room_type:, start_date:, end_date:)
      @hotel = hotel
      @room_type = room_type
      @start_date = start_date.to_date
      @end_date = end_date.to_date
    end

    def call
      ActiveRecord::Base.transaction do
        (@start_date..@end_date).each do |date|
          sync_date(date)
        end
      end

      trigger_channel_sync
    end

    private

    def sync_date(date)
      inventory = @room_type.room_inventories.find_or_initialize_by(date: date)

      # 1. Total rooms for this type
      all_room_numbers = @room_type.room_numbers.map(&:to_s).reject(&:blank?)

      # 2. Find blocked rooms (excluding finished ones)
      blocked_numbers = @hotel.room_blocks.active_on(date)
                             .where(room_type: @room_type)
                             .pluck(:room_number)
                             .map(&:to_s)
                             .uniq

      # 3. Calculate Available Room Numbers for Inventory (All - Blocked)
      # Note: This logic assumes that any room NOT blocked is available for sale.
      # If there were manual removals, they might be overridden here unless we have a way to track them.
      # For now, we prioritize the automatic sync between blocks and inventory.
      available_rooms = all_room_numbers - blocked_numbers
      inventory.available_room_numbers = available_rooms

      # 4. Calculate Quantity = Available - Occupied
      # We count rooms taken by bookings for this room type on this date
      occupied_count = @hotel.bookings.revenue_generating
                             .joins(:booking_rooms)
                             .where(":date >= bookings.check_in::date AND :date < bookings.check_out::date", date: date)
                             .where(booking_rooms: { room_type_id: @room_type.id })
                             .count("booking_rooms.id")

      inventory.quantity = [ 0, available_rooms.size - occupied_count ].max
      inventory.status = "open" if inventory.new_record?

      inventory.save!
    end

    def trigger_channel_sync
      return if @hotel.preferred_channel_manager.blank?
      ChannelManagers::SyncJob.perform_later(
        @hotel.id,
        @start_date,
        @end_date,
        sync_availability: true,
        sync_rates: false,
        sync_restrictions: false
      )
    end
  end
end

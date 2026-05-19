module HotelOps
  class BulkUpdateInventory
    def initialize(hotel:, room_type:, start_date:, end_date:, quantity: nil, status: "open", user:, room_numbers: nil)
      @hotel = hotel
      @room_type = room_type
      @start_date = start_date.to_date
      @end_date = end_date.to_date
      @quantity = quantity
      @status = status
      @user = user
      @room_numbers = room_numbers
    end

    def call
      Thread.current[:skip_ari_sync] = true
      ActiveRecord::Base.transaction do
        (@start_date..@end_date).each do |date|
          inventory = @room_type.room_inventories.find_or_initialize_by(date: date)
          old_quantity = inventory.quantity
          old_status = inventory.status
          old_rooms = inventory.available_room_numbers

          inventory.status = @status
          if @room_numbers.is_a?(Array)
            if @room_type.room_numbers.any?
              # 1. Filter room numbers to only those that belong to this RoomType
              valid_rooms = @room_numbers & @room_type.room_numbers
              inventory.available_room_numbers = valid_rooms

              # 2. Calculate net quantity (Selected - Already Booked)
              occupied_count = @hotel.bookings.revenue_generating
                                     .joins(:booking_rooms)
                                     .where(":date >= bookings.check_in AND :date < bookings.check_out", date: date)
                                     .where(booking_rooms: { room_number: valid_rooms })
                                     .distinct
                                     .count(:id)
              inventory.quantity = [ 0, valid_rooms.size - occupied_count ].max
            else
              # If RoomNumbers mode is used but this type has none, use global quantity if provided
              inventory.available_room_numbers = []
              inventory.quantity = @quantity if @quantity
            end
          else
            # Traditional quantity mode
            inventory.available_room_numbers = []
            inventory.quantity = @quantity || @room_type.quantity
          end
          inventory.save!

          # Log change
          if old_quantity != inventory.quantity || old_status != inventory.status || old_rooms != inventory.available_room_numbers
            @hotel.inventory_audit_logs.create!(
              room_type: @room_type,
              user: @user,
              action_type: "inventory_update",
              old_value: { date: date, quantity: old_quantity, status: old_status, room_numbers: old_rooms },
              new_value: { date: date, quantity: inventory.quantity, status: inventory.status, room_numbers: inventory.available_room_numbers },
              metadata: { source: "bulk_editor" }
            )
          end
        end

        # Trigger ARI Sync if CM is connected
        if @hotel.preferred_channel_manager.present?
          ChannelManagers::SyncJob.perform_later(
            @hotel.id,
            @start_date,
            @end_date,
            sync_availability: true,
            sync_rates: false,
            sync_restrictions: false
          )
        end

        { success: true }
      end
    rescue => e
      { success: false, error: e.message }
    ensure
      Thread.current[:skip_ari_sync] = nil
    end
  end
end

module HotelOps
  class BulkUpdateInventory
    def initialize(hotel:, room_type:, start_date:, end_date:, quantity:, status: "open", user:)
      @hotel = hotel
      @room_type = room_type
      @start_date = start_date.to_date
      @end_date = end_date.to_date
      @quantity = quantity
      @status = status
      @user = user
    end

    def call
      ActiveRecord::Base.transaction do
        (@start_date..@end_date).each do |date|
          inventory = @room_type.room_inventories.find_or_initialize_by(date: date)
          old_quantity = inventory.quantity
          old_status = inventory.status

          inventory.quantity = @quantity
          inventory.status = @status
          inventory.save!

          if old_quantity != @quantity || old_status != @status
            @hotel.inventory_audit_logs.create!(
              room_type: @room_type,
              user: @user,
              action_type: "inventory_update",
              old_value: { date: date, quantity: old_quantity, status: old_status },
              new_value: { date: date, quantity: @quantity, status: @status },
              metadata: { source: "bulk_editor" }
            )
          end
        end
        { success: true }
      end
    rescue => e
      { success: false, error: e.message }
    end
  end
end

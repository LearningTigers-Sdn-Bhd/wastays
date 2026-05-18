module BookingEngine
  class HoldInventory
    def initialize(quote)
      @quote = quote
      @stay_dates = (quote.check_in...quote.check_out).to_a
    end

    def call
      ActiveRecord::Base.transaction do
        @quote.booking_quote_items.includes(:room_type).each do |item|
          room_type = item.room_type
          quantity = item.quantity

          # Decrease quantity for each night
          @stay_dates.each do |date|
            inventory = room_type.room_inventories.lock.find_by!(date: date)

            # Check again if enough inventory is available
            if inventory.quantity < quantity
              raise "Not enough inventory for #{room_type.name} on #{date}"
            end

            inventory.update!(quantity: inventory.quantity - quantity)
          end
        end
        true
      end
    rescue => e
      false
    end
  end
end

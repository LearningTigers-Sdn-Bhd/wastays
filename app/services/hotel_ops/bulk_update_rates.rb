module HotelOps
  class BulkUpdateRates
    def initialize(hotel:, room_type:, start_date:, end_date:, price:, currency: 'MYR', user:)
      @hotel = hotel
      @room_type = room_type
      @start_date = start_date.to_date
      @end_date = end_date.to_date
      @price = price
      @currency = currency
      @user = user
    end

    def call
      ActiveRecord::Base.transaction do
        (@start_date..@end_date).each do |date|
          rate = @room_type.room_rates.find_or_initialize_by(date: date)
          old_price = rate.price
          rate.price = @price
          rate.currency = @currency
          rate.save!

          # Log change if price actually changed or new record
          if old_price != @price
            @hotel.inventory_audit_logs.create!(
              room_type: @room_type,
              user: @user,
              action_type: 'rate_update',
              old_value: { date: date, price: old_price.to_f },
              new_value: { date: date, price: @price.to_f },
              metadata: { source: 'bulk_editor' }
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

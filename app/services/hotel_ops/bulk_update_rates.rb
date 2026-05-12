module HotelOps
  class BulkUpdateRates
    def initialize(hotel:, rate_plan:, start_date:, end_date:, price:, currency: "MYR", user:)
      @hotel = hotel
      @rate_plan = rate_plan
      @room_type = rate_plan.room_type
      @start_date = start_date.to_date
      @end_date = end_date.to_date
      @price = price
      @currency = currency
      @user = user
    end

    def call
      ActiveRecord::Base.transaction do
        (@start_date..@end_date).each do |date|
          # Always find or create the Standard Rate record for this date
          rate = @room_type.room_rates.find_or_initialize_by(date: date)
          rate.rate_plan = @rate_plan
          old_price = rate.price
          rate.price = @price
          rate.currency = @currency
          rate.save!

          # Log change if price actually changed or new record
          if old_price != @price
            @hotel.inventory_audit_logs.create!(
              room_type: @room_type,
              user: @user,
              action_type: "rate_update",
              old_value: { date: date, price: old_price.to_f, rate_plan_id: @rate_plan.id },
              new_value: { date: date, price: @price.to_f, rate_plan_id: @rate_plan.id },
              metadata: { source: "bulk_editor" }
            )
          end
        end

        # Trigger ARI Sync if CM is connected
        if @hotel.preferred_channel_manager.present?
          ChannelManagers::SyncJob.perform_later(@hotel.id, @start_date, @end_date)
          
          # Clear the sync buffer to prevent redundant calls from RoomRate after_commit hooks
          # which usually wait 30 seconds to flush.
          window_key = "channex:ari:window:#{@hotel.id}"
          scheduled_key = "channex:ari:scheduled:#{@hotel.id}"
          Rails.cache.delete(window_key)
          Rails.cache.delete(scheduled_key)
        end

        { success: true }
      end
    rescue => e
      { success: false, error: e.message }
    end
  end
end

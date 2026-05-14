module HotelOps
  class BulkUpdateRates
    def initialize(hotel:, rate_plan:, start_date:, end_date:, price:, currency: "MYR", user:, min_stay: nil, max_stay: nil, closed_to_arrival: nil, closed_to_departure: nil, stop_sell: nil)
      @hotel = hotel
      @rate_plan = rate_plan
      @room_type = rate_plan.room_type
      @start_date = start_date.to_date
      @end_date = end_date.to_date
      @price = price
      @currency = CurrencyCatalog.valid?(currency) ? CurrencyCatalog.normalize(currency) : rate_plan.currency
      @user = user
      @min_stay = min_stay
      @max_stay = max_stay
      @closed_to_arrival = closed_to_arrival
      @closed_to_departure = closed_to_departure
      @stop_sell = stop_sell
    end

    def call
      Thread.current[:skip_ari_sync] = true
      ActiveRecord::Base.transaction do
        (@start_date..@end_date).each do |date|
          # Find or create record for this specific date, plan and currency
          rate = @rate_plan.room_rates.find_or_initialize_by(date: date, currency: @currency)
          rate.room_type = @room_type
          old_price = rate.price
          rate.price = @price
          rate.min_stay = @min_stay if @min_stay.present?
          rate.max_stay = @max_stay if @max_stay.present?
          rate.closed_to_arrival = @closed_to_arrival if !@closed_to_arrival.nil?
          rate.closed_to_departure = @closed_to_departure if !@closed_to_departure.nil?
          rate.stop_sell = @stop_sell if !@stop_sell.nil?
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

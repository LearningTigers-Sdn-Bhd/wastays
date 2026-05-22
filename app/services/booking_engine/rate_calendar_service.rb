module BookingEngine
  class RateCalendarService
    Day = Struct.new(:date, :min_price, :available, :rooms_left, keyword_init: true)
    MAX_WINDOW_DAYS = 180

    def initialize(hotel:, start_date:, end_date:, room_count: 1)
      @hotel = hotel
      @start_date = start_date
      @end_date = end_date
      @room_count = [ room_count.to_i, 1 ].max
    end

    def call
      validate!
      dates = (@start_date..@end_date).to_a
      room_types = @hotel.room_types
      room_type_ids = room_types.pluck(:id)

      # Determine if partner/corporate logic is available
      partner = @hotel.respond_to?(:partners) && @partner_code.present? ? @hotel.partners.find_by(code: @partner_code) : nil

      # MIN price only over room types that are actually available that night
      # We prefer explicit RoomRate prices over the room_type base_price fallback
      # if a record exists.
      price_expression = if partner.present?
        "LEAST(price, COALESCE(corporate_price, price))"
      else
        "price"
      end

      rates = RoomRate
        .joins("INNER JOIN room_inventories ri
                ON ri.room_type_id = room_rates.room_type_id
               AND ri.date         = room_rates.date")
        .where(room_type_id: room_type_ids, date: dates)
        .where(ri: { status: "open" })
        .where("ri.quantity >= ?", @room_count)
        .group("room_rates.date")
        .minimum(price_expression)

      inventories = RoomInventory
        .where(room_type_id: room_type_ids, date: dates, status: "open")
        .where("quantity >= ?", @room_count)
        .group(:date)
        .sum(:quantity)

      currency = RoomRate
        .where(room_type_id: room_type_ids, date: dates)
        .limit(1)
        .pluck(:currency)
        .first || @hotel.property_policy&.currency || "MYR"

      # Pre-calculate which dates have ANY available room type inventory
      # This handles cases where a date has inventory but NO RoomRate record yet
      dates_with_inventory = RoomInventory
        .where(room_type_id: room_type_ids, date: dates, status: "open")
        .where("quantity >= ?", @room_count)
        .pluck(:date).uniq

      # Find the minimum base price of room types that have inventory but NO RoomRate for specific dates
      # This is a bit complex to do in one query, so we'll handle it during mapping.
      base_prices_by_room_type = room_types.where("max_adults >= ?", @room_count).pluck(:id, :base_price).to_h

      days = dates.map do |d|
        rooms_left = inventories[d].to_i

        # If we have an explicit rate from RoomRate, use it (it wins over base_price)
        price = rates[d]

        # If no explicit rate but we have inventory, use the min base price of available room types
        if price.nil? && dates_with_inventory.include?(d)
          # We need to know which room types have inventory on this date but no rate
          # For simplicity and performance, we'll use the global min_base_price as the fallback
          # but only if no explicit rates were found for any room type on this date.
          price = base_prices_by_room_type.values.min
        end

        Day.new(
          date: d,
          min_price: price&.to_f,
          available: price.present? && rooms_left > 0,
          rooms_left: rooms_left
        )
      end

      { currency: currency, days: days }
    end

    private

    def validate!
      raise ArgumentError, "end_date before start_date" if @end_date < @start_date
      raise ArgumentError, "window too large" if (@end_date - @start_date).to_i > MAX_WINDOW_DAYS
    end
  end
end

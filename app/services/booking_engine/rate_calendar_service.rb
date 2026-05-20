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
      room_type_ids = @hotel.room_types.select(:id)

      # MIN price only over room types that are actually available that night
      price_expression = "price"

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

      days = dates.map do |d|
        rooms_left = inventories[d].to_i
        price = rates[d]
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

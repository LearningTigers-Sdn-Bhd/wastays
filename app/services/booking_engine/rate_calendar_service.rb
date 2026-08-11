module BookingEngine
  class RateCalendarService
    Day = Struct.new(:date, :min_price, :available, :rooms_left, :min_stay, :max_stay, keyword_init: true)
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
      room_types = @hotel.room_types.includes(:rate_plans, room_type_rate_plans: :occupancy_prices).to_a
      room_type_ids = room_types.pluck(:id)

      rates = RoomRate
        .joins(:rate_plan)
        .joins("INNER JOIN room_inventories ri
                ON ri.room_type_id = room_rates.room_type_id
               AND ri.date         = room_rates.date")
        .where(room_type_id: room_type_ids, date: dates)
        .where(rate_plans: { hotel_id: @hotel.id, archived_at: nil, kind: RatePlan.kinds_for(:public) })
        .where(ri: { status: "open" })
        .where("ri.quantity >= ?", @room_count)
        .group("room_rates.date")
        .minimum(:price)

      available_inventories = RoomInventory
        .where(room_type_id: room_type_ids, date: dates, status: "open")
        .where("quantity >= ?", @room_count)

      inventories = available_inventories
        .group(:date)
        .sum(:quantity)

      available_room_type_ids = available_inventories
        .pluck(:date, :room_type_id)
        .group_by(&:first)
        .transform_values { |pairs| pairs.map(&:last) }

      currency = RoomRate
        .where(room_type_id: room_type_ids, date: dates)
        .limit(1)
        .pluck(:currency)
        .first || @hotel.property_policy&.currency || "MYR"

      eligible_room_rates = RoomRate
        .joins(:rate_plan)
        .joins("INNER JOIN room_inventories ri
                ON ri.room_type_id = room_rates.room_type_id
               AND ri.date         = room_rates.date")
        .where(room_type_id: room_type_ids, date: dates)
        .where(rate_plans: { hotel_id: @hotel.id, archived_at: nil, kind: RatePlan.kinds_for(:public) })
        .where(ri: { status: "open" })
        .where("ri.quantity >= ?", @room_count)
      room_rates_data = eligible_room_rates
        .select("room_rates.date, room_rates.min_stay, room_rates.max_stay")
        .to_a

      rates_for_resolution = RoomRate
        .where(room_type_id: room_type_ids, date: dates)
        .to_a
        .group_by(&:room_type_id)

      rates_by_date = room_rates_data.group_by(&:date)

      days = dates.map do |d|
        rooms_left = inventories[d].to_i

        # If we have an explicit rate from RoomRate, use it (it wins over base_price)
        price = rates[d]
        if price.nil?
          price = fallback_price(
            date: d,
            room_types: room_types,
            available_room_type_ids: available_room_type_ids[d],
            room_rates_by_room_type: rates_for_resolution
          )
        end

        day_rates = rates_by_date[d] || []
        if day_rates.empty?
          min_stay = nil
          max_stay = nil
        else
          min_stay = day_rates.any? { |r| r.min_stay.nil? } ? nil : day_rates.map(&:min_stay).compact.min
          max_stay = day_rates.any? { |r| r.max_stay.nil? } ? nil : day_rates.map(&:max_stay).compact.max
        end

        Day.new(
          date: d,
          min_price: price&.to_f,
          available: price.present? && rooms_left > 0,
          rooms_left: rooms_left,
          min_stay: min_stay,
          max_stay: max_stay
        )
      end

      { currency: currency, days: days }
    end

    private

    def fallback_price(date:, room_types:, available_room_type_ids:, room_rates_by_room_type:)
      return if available_room_type_ids.blank?

      eligible_ids = available_room_type_ids.to_set
      room_types.filter_map do |room_type|
        next unless eligible_ids.include?(room_type.id)

        room_type.rate_plans.filter_map do |rate_plan|
          next unless rate_plan.bookable_by?(:public)

          assignment = room_type.room_type_rate_plans.find { |item| item.rate_plan_id == rate_plan.id }
          Rates::ResolveEffectiveNightlyPrice.call(
            room_type: room_type,
            rate_plan: rate_plan,
            date: date,
            adults: 2,
            room_rates: room_rates_by_room_type.fetch(room_type.id, []),
            room_type_rate_plan: assignment
          ).amount
        end.min
      end.min
    end

    def validate!
      raise ArgumentError, "end_date before start_date" if @end_date < @start_date
      raise ArgumentError, "window too large" if (@end_date - @start_date).to_i > MAX_WINDOW_DAYS
    end
  end
end

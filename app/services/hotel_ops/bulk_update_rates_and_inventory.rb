module HotelOps
  class BulkUpdateRatesAndInventory
    def initialize(hotel:, room_type_ids: [], start_date:, end_date:, price: nil, quantity: nil, status: nil, user:)
      @hotel = hotel
      @room_type_ids = room_type_ids
      @start_date = start_date.to_date
      @end_date = end_date.to_date
      @price = price.presence&.to_f
      @quantity = quantity.presence&.to_i
      @status = status.presence
      @user = user
    end

    def call
      room_types = @hotel.room_types
      room_types = room_types.where(id: @room_type_ids) if @room_type_ids.present?

      ActiveRecord::Base.transaction do
        room_types.each do |rt|
          update_rates(rt) if @price
          update_inventory(rt) if @quantity || @status
        end
        { success: true }
      end
    rescue => e
      { success: false, error: e.message }
    end

    private

    def update_rates(room_type)
      HotelOps::BulkUpdateRates.new(
        hotel: @hotel,
        room_type: room_type,
        start_date: @start_date,
        end_date: @end_date,
        price: @price,
        user: @user
      ).call
    end

    def update_inventory(room_type)
      HotelOps::BulkUpdateInventory.new(
        hotel: @hotel,
        room_type: room_type,
        start_date: @start_date,
        end_date: @end_date,
        quantity: @quantity || room_type.quantity,
        status: @status || "open",
        user: @user
      ).call
    end
  end
end

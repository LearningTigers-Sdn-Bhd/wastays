require "ostruct"

module BookingEngine
  class CreateQuote
    def initialize(params)
      @hotel = Hotel.find(params[:hotel_id])
      @room_type = @hotel.room_types.find(params[:room_type_id])
      @check_in = parse_date(params[:check_in])
      @check_out = parse_date(params[:check_out])
      @adults = (params[:adults].presence || 2).to_i
      @children = (params[:children].presence || 0).to_i
      @room_count = (params[:room_count].presence || 1).to_i
      @guest_name = params[:guest_name]
      @guest_email = params[:guest_email]
      @guest_phone = params[:guest_phone]
    end

    def call
      validation_error = validate_dates
      return OpenStruct.new(success?: false, message: validation_error) if validation_error.present?

      BookingQuote.transaction do
        # 1. Revalidate availability one last time
        availability_service = BookingEngine::AvailabilityService.new(
          check_in: @check_in,
          check_out: @check_out,
          adults: @adults,
          children: @children,
          room_count: @room_count
        )

        available_rooms = availability_service.available_rooms_for_hotel(@hotel)
        unless available_rooms.include?(@room_type)
          return OpenStruct.new(success?: false, message: "Room is no longer available for these dates.")
        end

        # 2. Calculate total amount and nightly rates
        stay_dates = (@check_in...@check_out).to_a
        nightly_rates = @room_type.room_rates.where(date: stay_dates).index_by(&:date)
        total_amount = availability_service.calculate_total_price(@room_type)

        # 3. Create Quote with snapshots
        quote = BookingQuote.new(
          hotel: @hotel,
          check_in: @check_in,
          check_out: @check_out,
          adults: @adults,
          children: @children,
          total_amount: total_amount,
          currency: @room_type.room_rates.first&.currency || "MYR",
          expires_at: 15.minutes.from_now,
          hotel_snapshot: @hotel.as_json,
          cancellation_policy_snapshot: @hotel.property_policy&.cancellation_policy,
          guest_name: @guest_name,
          guest_email: @guest_email,
          guest_phone: @guest_phone
        )

        if quote.save
          # 4. Create Quote Item
          quote.booking_quote_items.create!(
            room_type: @room_type,
            quantity: @room_count,
            subtotal: total_amount,
            room_type_snapshot: @room_type.as_json,
            nightly_rate_snapshot: nightly_rates.transform_values(&:as_json),
            occupancy_snapshot: { max_adults: @room_type.max_adults, max_children: @room_type.max_children }
          )

          # 5. Place Inventory Hold
          hold_service = BookingEngine::HoldInventory.new(quote)
          if hold_service.call
            OpenStruct.new(success?: true, quote: quote)
          else
            raise ActiveRecord::Rollback, "Failed to hold inventory"
          end
        else
          OpenStruct.new(success?: false, message: quote.errors.full_messages.to_sentence)
        end
      end
    rescue => e
      OpenStruct.new(success?: false, message: "An error occurred: #{e.message}")
    end

    private

    def parse_date(date_param)
      return date_param if date_param.is_a?(Date)
      return nil if date_param.blank?

      Date.parse(date_param)
    rescue ArgumentError
      nil
    end

    def validate_dates
      return "Please select check-in and check-out dates." if @check_in.blank? || @check_out.blank?
      return "Check-out date must be after check-in date." if @check_out <= @check_in

      nil
    end
  end
end

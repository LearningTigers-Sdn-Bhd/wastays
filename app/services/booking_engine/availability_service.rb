module BookingEngine
  class AvailabilityService
    def initialize(params)
      @params = params
      @city = params[:city]
      @check_in = parse_date(params[:check_in]) || Date.today
      @check_out = parse_date(params[:check_out]) || Date.tomorrow
      @adults = (params[:adults] || 2).to_i
      @children = (params[:children] || 0).to_i
      @room_count = (params[:room_count] || 1).to_i
    end

    def find_available_hotels
      # 1. Base query: active hotels
      hotels = Hotel.where(status: ['approved', 'live'])
      hotels = hotels.where("city ILIKE ?", "%#{@city}%") if @city.present?

      # 2. Filter by availability
      # Note: This is simplified for MVP. For production with many hotels, use specialized indexing.
      hotels.select do |hotel|
        available_rooms_for_hotel(hotel).any?
      end
    end

    def available_rooms_for_hotel(hotel)
      # Get stay dates (excluding check-out day)
      stay_dates = (@check_in...@check_out).to_a
      return [] if stay_dates.empty?

      # 1. Basic occupancy filter
      # In V3, we assume guest specifies TOTAL adults/children for the whole booking.
      # For now, let's say ANY room type that can fit the guests is a candidate.
      potential_room_types = hotel.room_types.where("max_adults >= ?", @adults)

      # 2. Date-based availability & rate check
      available_room_types = potential_room_types.select do |room_type|
        # Check inventory for all stay dates
        inventories = room_type.room_inventories.where(date: stay_dates)
        
        # Must have open inventory with quantity >= required room_count for EVERY stay date
        inventory_ok = (inventories.count == stay_dates.count) && 
                       inventories.all? { |inv| inv.status == 'open' && inv.quantity >= @room_count }

        next false unless inventory_ok

        # Check rates for all stay dates
        rates = room_type.room_rates.where(date: stay_dates)
        
        # Must have rate record for EVERY stay date
        rates_ok = (rates.count == stay_dates.count)
        
        rates_ok
      end

      available_room_types
    end

    def calculate_total_price(room_type)
      stay_dates = (@check_in...@check_out).to_a
      rates = room_type.room_rates.where(date: stay_dates)
      rates.sum(:price) * @room_count
    end

    private

    def parse_date(date_param)
      return date_param if date_param.is_a?(Date)
      return nil if date_param.blank?

      begin
        Date.parse(date_param)
      rescue ArgumentError
        nil
      end
    end
  end
end

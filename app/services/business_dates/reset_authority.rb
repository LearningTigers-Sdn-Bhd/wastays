# frozen_string_literal: true

module BusinessDates
  class ResetAuthority
    def self.call!(**kwargs)
      new(**kwargs).call!
    end

    def initialize(hotel:, date: nil)
      @hotel = hotel
      @date = date
    end

    def call!
      HotelBusinessDate.transaction do
        @hotel.lock!
        replacement_date = (@date || @hotel.business_date_for(Time.current)).to_date
        @hotel.hotel_business_dates.delete_all
        HotelBusinessDate.create!(
          hotel: @hotel,
          business_date: replacement_date,
          status: "open",
          opened_at: Time.current,
          blockers_snapshot: {}
        )
      end
    rescue ActiveRecord::RecordNotUnique => e
      raise HotelBusinessDate::InvalidTransition, "Another current accounting business date already exists: #{e.message}"
    end
  end
end

# frozen_string_literal: true

# `Date.current`/`Time.current` resolve in the app's global zone (UTC), but
# `Booking#check_in=`/`#check_out=` anchor to the hotel's local timezone
# (`Bookings::ScheduledStay.at_hotel_time`), and hotel-scoped queries compute
# "today" via `hotel.hotel_time_zone`. The two disagree on the calendar date
# for several hours a day near the UTC/hotel-zone boundary, so specs that need
# "today" for a hotel-scoped date must compute it the same way the app does.
module HotelTimeHelpers
  def hotel_today(hotel)
    Time.current.in_time_zone(hotel.hotel_time_zone).to_date
  end
end

RSpec.configure do |config|
  config.include HotelTimeHelpers, type: :system
  config.include HotelTimeHelpers, type: :request
end

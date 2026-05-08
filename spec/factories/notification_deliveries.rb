FactoryBot.define do
  factory :notification_delivery do
    hotel
    booking { association :booking, hotel: hotel }
    notification_type { "check_in_confirmation" }
    channel { "email" }
    trigger_event { "booking_checked_in" }
    status { "pending" }
    sequence(:idempotency_key) { |n| "delivery-key-#{n}" }
    payload { { guest_name: booking.guest_name, hotel_name: hotel.name, checked_in_at: Time.current.iso8601 } }
  end
end

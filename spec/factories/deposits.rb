# frozen_string_literal: true

FactoryBot.define do
  factory :deposit do
    association :booking
    hotel { booking.hotel }
    booking_folio { association(:booking_folio, booking: booking, hotel: hotel) }
    hold_type { "security" }
    status { "collected" }
    amount { 100.0 }
    currency { "MYR" }
    payment_method { "cash" }
  end
end

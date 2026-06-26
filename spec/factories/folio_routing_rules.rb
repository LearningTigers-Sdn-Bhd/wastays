# frozen_string_literal: true

FactoryBot.define do
  factory :folio_routing_rule do
    association :booking
    hotel { booking.hotel }
    transaction_code { association(:transaction_code, hotel: hotel) }
    target_folio { association(:booking_folio, :secondary, booking: booking, hotel: hotel) }
    active { true }
  end
end

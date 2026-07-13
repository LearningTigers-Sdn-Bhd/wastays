# frozen_string_literal: true

FactoryBot.define do
  factory :booking_billing_party do
    association :booking
    hotel { booking.hotel }
    party_kind { "company" }
    booking_guest { nil }
    hotel_corporate_account { association :hotel_corporate_account, hotel: hotel }

    trait :company do
      party_kind { "company" }
      booking_guest { nil }
      hotel_corporate_account { association :hotel_corporate_account, hotel: hotel }
    end
  end
end

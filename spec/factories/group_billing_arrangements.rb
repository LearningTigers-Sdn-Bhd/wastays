# frozen_string_literal: true

FactoryBot.define do
  factory :group_billing_arrangement do
    association :group_booking
    hotel { group_booking.hotel }
    name { "Guest responsibility" }
    payer_type { "guest" }
    settlement_type { "cash_bank" }
    status { "active" }

    trait :company do
      payer_type { "company" }
      hotel_corporate_account { association :hotel_corporate_account, hotel: hotel }
      name { "Corporate room charges" }
    end
  end
end

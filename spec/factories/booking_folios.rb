FactoryBot.define do
  factory :booking_folio do
    association :booking
    booking_room { nil }
    hotel { booking.hotel }
    sequence(:folio_number) { |n| n }
    name { "Guest Folio" }
    folio_type { "guest" }
    payer_type { "guest" }
    hotel_corporate_account { payer_type == "company" ? association(:hotel_corporate_account, hotel: hotel) : nil }
    is_primary { true }
    currency { booking.currency.presence || "MYR" }
    opened_at { Time.current }
    status { "open" }

    trait :secondary do
      name { "Company Folio" }
      folio_type { "external" }
      payer_type { "company" }
      is_primary { false }
    end
  end
end

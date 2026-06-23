FactoryBot.define do
  factory :booking_folio do
    association :booking
    hotel { booking.hotel }
    sequence(:folio_number) { |n| n }
    name { "Guest Folio" }
    folio_type { "guest" }
    payer_type { "guest" }
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

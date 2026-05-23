FactoryBot.define do
  factory :booking_folio do
    association :booking
    hotel { booking.hotel }
    sequence(:folio_number) { |n| n }
    status { "open" }
  end
end

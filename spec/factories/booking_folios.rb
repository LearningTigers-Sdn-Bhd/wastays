FactoryBot.define do
  factory :booking_folio do
    association :booking
    sequence(:folio_number) { |n| n }
    status { "open" }
  end
end

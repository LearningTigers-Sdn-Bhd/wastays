FactoryBot.define do
  factory :booking_note do
    association :booking
    association :user
    body { "Guest requested late check-in." }
  end
end

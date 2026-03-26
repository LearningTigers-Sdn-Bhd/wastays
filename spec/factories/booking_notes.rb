FactoryBot.define do
  factory :booking_note do
    booking { nil }
    body { "MyText" }
    created_by { nil }
  end
end

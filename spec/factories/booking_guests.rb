FactoryBot.define do
  factory :booking_guest do
    booking { nil }
    guest { nil }
    is_primary { false }
  end
end

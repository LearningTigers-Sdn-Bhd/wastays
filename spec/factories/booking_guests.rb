FactoryBot.define do
  factory :booking_guest do
    association :booking
    association :guest
    is_primary { false }
  end
end

FactoryBot.define do
  factory :user_hotel_access do
    association :user
    association :hotel
    association :role
  end
end

FactoryBot.define do
  factory :hotel do
    association :account
    name { Faker::Company.name }
    address { Faker::Address.street_address }
    city { Faker::Address.city }
    country { "Malaysia" }
    star_rating { 4 }
    status { "registered" }
  end
end

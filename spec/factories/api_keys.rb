FactoryBot.define do
  factory :api_key do
    association :bearer, factory: :hotel
    status { "active" }
  end
end

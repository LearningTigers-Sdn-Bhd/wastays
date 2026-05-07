FactoryBot.define do
  factory :prospect do
    association :hotel
    guest { nil }
    sequence(:phone_number) { |n| "+60123456#{n.to_s.rjust(3, '0')}" }
    name { Faker::Name.name }
    stage { "cold" }
    last_contact { Time.current }
  end
end

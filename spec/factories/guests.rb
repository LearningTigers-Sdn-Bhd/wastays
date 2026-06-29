FactoryBot.define do
  factory :guest do
    name { Faker::Name.name }
    sequence(:email) { |n| "guest#{n}@example.com" }
    phone { "+60123456789" }
    government_id { "A1234567" }
    city { "Kuala Lumpur" }
    country { "Malaysia" }
    gender { "male" }
    document_type { "passport" }
    metadata { {} }
  end
end

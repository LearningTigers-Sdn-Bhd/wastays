FactoryBot.define do
  factory :partner do
    hotel
    sequence(:name) { |n| "Partner #{n}" }
    sequence(:code) { |n| "CORP#{n}" }
    domain { "example.com" }
  end
end

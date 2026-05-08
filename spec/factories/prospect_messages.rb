FactoryBot.define do
  factory :prospect_message do
    association :prospect
    direction { "inbound" }
    body { "Hello there" }
    sent_at { Time.current }
  end
end

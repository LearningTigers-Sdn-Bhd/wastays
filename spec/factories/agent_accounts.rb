FactoryBot.define do
  factory :agent_account do
    association :hotel
    name { "Test Agent" }
    sequence(:agent_code) { |n| "AGENT#{n}" }
    account_type { "company" }
    contact_email { "agent@example.com" }
    contact_phone { "12345678" }
  end
end

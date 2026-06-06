FactoryBot.define do
  factory :hotel_team_config do
    association :hotel
    name { "Finance Team" }
    description { "Main finance observability group" }
    emails { "finance@example.com" }
    frequency { 86400 }
    template_type { "financial_observability" }
  end
end

# frozen_string_literal: true

FactoryBot.define do
  factory :onboarding_corporate_draft do
    hotel
    sequence(:email) { |n| "accounts#{n}@corporate.example.com" }
    company_name { "Acme Sdn Bhd" }
    account_type { "company" }
    relationship_type { "standard" }
    credit_currency { "MYR" }
  end
end

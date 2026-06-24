# frozen_string_literal: true

FactoryBot.define do
  factory :hotel_corporate_account do
    association :hotel
    corporate_account { association :account, :corporate }
    corporate_type { "company" }
    relationship_type { "standard" }
    direct_bill_enabled { false }
    credit_currency { hotel.default_currency }
    status { "active" }
  end
end

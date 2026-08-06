# frozen_string_literal: true

FactoryBot.define do
  factory :hotel_corporate_account do
    association :hotel
    corporate_account { association :account, :corporate }
    relationship_type { "standard" }
    direct_bill_enabled { false }
    credit_currency { hotel.default_currency }
    status { "active" }

    # direct_bill_enabled is derived from relationship_type (see
    # HotelCorporateAccount#sync_direct_bill_enabled); it can't be set
    # independently, so use this trait instead of `direct_bill_enabled: true`.
    trait :direct_bill do
      relationship_type { "direct_bill" }
    end
  end
end

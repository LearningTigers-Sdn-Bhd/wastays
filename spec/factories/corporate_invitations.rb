# frozen_string_literal: true

FactoryBot.define do
  factory :corporate_invitation do
    association :account
    hotel { association :hotel, account: account }
    invited_by_user { association :user, account: account }
    sequence(:email) { |n| "corporate#{n}@example.com" }
    relationship_type { "standard" }
    direct_bill_enabled { false }
    credit_currency { "MYR" }
    token_digest { Invitation.digest("corporate-token-#{SecureRandom.hex(8)}") }
    expires_at { Invitation::EXPIRY.from_now }

    # direct_bill_enabled is derived from relationship_type (see
    # CorporateInvitation#sync_direct_bill_enabled); it can't be set
    # independently, so use this trait instead of `direct_bill_enabled: true`.
    trait :direct_bill do
      relationship_type { "direct_bill" }
    end
  end
end

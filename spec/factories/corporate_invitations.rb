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
  end
end

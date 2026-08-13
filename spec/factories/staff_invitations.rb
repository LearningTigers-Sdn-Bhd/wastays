# frozen_string_literal: true

FactoryBot.define do
  factory :staff_invitation do
    association :account
    hotel { association :hotel, account: account }
    role { association :role, account: account }
    invited_by_user { association :user, account: account }
    sequence(:email) { |n| "invited#{n}@example.com" }
    name { "Invited Staff" }
    token_digest { StaffInvitation.digest("token-#{SecureRandom.hex(8)}") }
    expires_at { StaffInvitation::EXPIRY.from_now }
    last_sent_at { Time.current }

    # Queued during onboarding with the send switch off: the invitation exists,
    # but the person has never been emailed.
    trait :held do
      last_sent_at { nil }
    end
  end
end

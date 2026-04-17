FactoryBot.define do
  factory :payout_batch do
    hotel { nil }
    amount { "9.99" }
    status { "MyString" }
    period_start { "2026-04-16" }
    period_end { "2026-04-16" }
    payout_at { "2026-04-16 15:58:54" }
    payout_reference { "MyString" }
    metadata { "" }
  end
end

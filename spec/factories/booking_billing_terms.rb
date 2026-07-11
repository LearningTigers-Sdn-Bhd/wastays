# frozen_string_literal: true

FactoryBot.define do
  factory :booking_billing_terms do
    association :booking_billing_party
    settlement_type { "cash_bank" }
  end
end

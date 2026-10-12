# frozen_string_literal: true

FactoryBot.define do
  factory :ar_payment_void do
    association :ar_payment
    association :voided_by, factory: :user
    reason { "Recorded in error" }
    voided_at { Time.current }
    metadata { {} }
  end
end

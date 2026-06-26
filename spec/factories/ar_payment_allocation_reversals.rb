# frozen_string_literal: true

FactoryBot.define do
  factory :ar_payment_allocation_reversal do
    association :ar_payment_allocation
    association :reversed_by, factory: :user
    reason { "Allocation correction" }
    reversed_at { Time.current }
    metadata { {} }
  end
end

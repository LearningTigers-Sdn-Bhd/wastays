# frozen_string_literal: true

FactoryBot.define do
  factory :financial_audit_event do
    association :hotel
    business_date { Date.current }
    event_type { "folio_transaction_created" }
    source { "staff" }
    metadata { {} }
    occurred_at { Time.current }
  end
end

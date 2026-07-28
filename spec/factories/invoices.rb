# frozen_string_literal: true

FactoryBot.define do
  factory :invoice do
    association :booking_folio, status: "closed"
    hotel { booking_folio.hotel }
    issued_by { booking_folio.closed_by }
    kind { "settled" }
    sequence(:invoice_number) { |number| 9_000_000 + number }
    invoice_year { Date.current.year }
    invoice_reference { "#{hotel.hotel_prefix}-#{kind == 'direct_bill' ? '4' : '7'}#{invoice_number.to_s.rjust(7, '0')}" }
    state { "finalized" }
    current_revision_number { 1 }
    issued_on { hotel.current_business_date }
    issued_at { Time.current }
    metadata { {} }

    transient do
      create_revision { true }
      revision_snapshot { {} }
    end

    after(:create) do |invoice, evaluator|
      if evaluator.create_revision
        create(:invoice_revision,
          invoice:,
          hotel: invoice.hotel,
          issued_by: invoice.issued_by,
          revision_number: 1,
          document_reference: invoice.invoice_reference,
          snapshot: evaluator.revision_snapshot,
          issued_at: invoice.issued_at)
      end
    end

    trait :direct_bill do
      kind { "direct_bill" }
    end
  end

  factory :invoice_revision do
    association :invoice, create_revision: false
    hotel { invoice.hotel }
    issued_by { invoice.issued_by }
    revision_number { invoice.current_revision_number }
    document_reference do
      revision_number == 1 ? invoice.invoice_reference : "#{invoice.invoice_reference}-#{revision_number}"
    end
    snapshot { {} }
    issued_at { Time.current }
  end
end

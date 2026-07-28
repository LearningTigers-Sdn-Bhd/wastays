# frozen_string_literal: true

FactoryBot.define do
  factory :folio_invoice do
    association :booking_folio, status: "closed"
    hotel { booking_folio.hotel }
    issued_by { booking_folio.closed_by }
    invoice_number { booking_folio.invoice_number || generate(:folio_invoice_number) }
    invoice_year { booking_folio.invoice_year || Date.current.year }
    invoice_reference { booking_folio.invoice_reference || "INV-#{invoice_year}-#{invoice_number}" }
    state { "finalized" }
    current_revision_number { 1 }
    issued_at { booking_folio.closed_at || Time.current }
    metadata { {} }

    transient do
      create_revision { true }
    end

    before(:create) do |invoice|
      invoice.booking_folio.update_columns(
        invoice_number: invoice.invoice_number,
        invoice_year: invoice.invoice_year,
        invoice_reference: invoice.invoice_reference
      )
    end

    after(:create) do |invoice, evaluator|
      document = create(:invoice,
        booking_folio: invoice.booking_folio,
        hotel: invoice.hotel,
        issued_by: invoice.issued_by,
        kind: "settled",
        invoice_number: invoice.invoice_number,
        invoice_year: invoice.invoice_year,
        invoice_reference: invoice.invoice_reference,
        state: invoice.state,
        current_revision_number: invoice.current_revision_number,
        issued_on: invoice.issued_at.to_date,
        issued_at: invoice.issued_at,
        legacy: invoice.legacy,
        create_revision: false)
      invoice.update_column(:invoice_id, document.id)

      if evaluator.create_revision
        create(:folio_invoice_revision,
          hotel: invoice.hotel,
          folio_invoice: invoice,
          issued_by: invoice.issued_by,
          revision_number: 1,
          document_reference: invoice.invoice_reference,
          issued_at: invoice.issued_at)
      end
    end
  end

  sequence(:folio_invoice_number)

  factory :folio_invoice_revision do
    association :folio_invoice, create_revision: false
    hotel { folio_invoice.hotel }
    issued_by { folio_invoice.issued_by }
    revision_number { folio_invoice.current_revision_number }
    document_reference do
      revision_number == 1 ? folio_invoice.invoice_reference : "#{folio_invoice.invoice_reference}-#{revision_number}"
    end
    snapshot { {} }
    issued_at { Time.current }
  end
end

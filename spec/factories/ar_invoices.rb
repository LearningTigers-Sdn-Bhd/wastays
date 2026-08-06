# frozen_string_literal: true

FactoryBot.define do
  factory :ar_invoice do
    association :booking_folio, :secondary
    hotel { booking_folio.hotel }
    hotel_corporate_account { booking_folio.hotel_corporate_account || association(:hotel_corporate_account, hotel: hotel) }
    sequence(:invoice_number) { |n| n }
    status { "open" }
    amount { 100.0 }
    paid_amount { 0 }
    outstanding_amount { amount }
    currency { booking_folio.currency.presence || "MYR" }
    issued_on { Date.current }
    due_on { issued_on + 30.days }
    metadata { {} }

    before(:create) do |receivable|
      snapshot = receivable.metadata.to_h["document_snapshot"]
      legacy = snapshot.blank?
      receivable.invoice ||= create(:invoice,
        :direct_bill,
        booking_folio: receivable.booking_folio,
        hotel: receivable.hotel,
        invoice_number: receivable.invoice_number,
        invoice_year: receivable.invoice_year || receivable.issued_on.year,
        invoice_reference: receivable.invoice_reference || DocumentIdentifiers::Issuer.format(
          hotel: receivable.hotel,
          type: :ar_invoice,
          year: receivable.invoice_year || receivable.issued_on.year,
          number: receivable.invoice_number
        ),
        issued_on: receivable.issued_on,
        issued_at: Time.current,
        legacy:,
        revision_snapshot: snapshot || { "legacy_generated" => true })
    end
  end
end

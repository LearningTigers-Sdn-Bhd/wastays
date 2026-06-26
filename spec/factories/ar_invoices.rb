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
  end
end

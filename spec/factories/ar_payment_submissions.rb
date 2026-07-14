# frozen_string_literal: true

FactoryBot.define do
  factory :ar_payment_submission do
    association :hotel_corporate_account
    hotel { hotel_corporate_account.hotel }
    association :submitted_by, factory: :user
    amount { 100.0 }
    currency { hotel.default_currency.presence || "MYR" }
    sequence(:reference_number) { |n| "SLIP-#{n}" }
    received_at { Date.current }
    payment_method { "bank_transfer" }
    status { "pending" }

    transient do
      # Skipped (nil) when hotel/hotel_corporate_account have been overridden into a mismatched
      # pair on purpose (e.g. to test that cross-hotel validation) — building a matching invoice
      # in that case would itself blow up on ArInvoice's own hotel-consistency validations.
      auto_invoice do
        next nil if hotel.blank? || hotel_corporate_account.blank? || hotel_corporate_account.hotel_id != hotel.id

        association(:ar_invoice,
          hotel: hotel,
          hotel_corporate_account: hotel_corporate_account,
          booking_folio: association(:booking_folio, :secondary,
            booking: association(:booking, hotel: hotel),
            hotel: hotel,
            hotel_corporate_account: hotel_corporate_account),
          amount: amount,
          outstanding_amount: amount,
          currency: currency)
      end
    end

    after(:build) do |submission, evaluator|
      submission.slip.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/sample_image.jpg")),
        filename: "slip.jpg",
        content_type: "image/jpeg"
      )

      next if submission.ar_payment_submission_allocations.any?
      next if evaluator.auto_invoice.blank?

      submission.ar_payment_submission_allocations.build(ar_invoice: evaluator.auto_invoice, amount: submission.amount)
    end
  end
end

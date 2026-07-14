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

    after(:build) do |submission|
      submission.slip.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/sample_image.jpg")),
        filename: "slip.jpg",
        content_type: "image/jpeg"
      )
    end
  end
end

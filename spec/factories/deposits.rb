# frozen_string_literal: true

FactoryBot.define do
  factory :deposit do
    association :booking
    group_booking { nil }
    hotel { booking&.hotel || group_booking.hotel }
    kind { "security" }
    status { kind == "security" ? "held" : "available" }
    amount { 100.to_d }
    currency { booking&.currency || group_booking&.bookings&.first&.currency || hotel.default_currency || "MYR" }
    payment_method { "cash" }
    received_at { Time.current }
    transaction_code do
      system_key = kind == "security" ? "security_deposit" : "bank_payment"
      category = kind == "security" ? "security_deposit" : "booking_payment"
      hotel.transaction_codes.find_by(system_key: system_key) ||
        association(:transaction_code,
          hotel: hotel,
          system_key: system_key,
          code: kind == "security" ? "SECDEP" : "BANK",
          name: kind == "security" ? "Security Deposit" : "Bank Transfer Payment",
          kind: "payment",
          category: category,
          gl_account_code: kind == "security" ? "2030" : "2020",
          system_required: true)
    end

    after(:create) do |deposit|
      deposit.deposit_movements.create!(
        movement_type: deposit.kind_security? ? "hold" : "receive",
        amount: deposit.amount,
        payment_method: deposit.payment_method,
        occurred_at: deposit.received_at
      )
    end

    trait :prepayment do
      kind { "prepayment" }
      status { "available" }
    end

    trait :group_owned do
      booking { nil }
      association :group_booking
    end
  end

  factory :deposit_movement do
    association :deposit
    movement_type { "release" }
    amount { 25.to_d }
    occurred_at { Time.current }
  end
end

# frozen_string_literal: true

FactoryBot.define do
  factory :deposit do
    association :booking
    hotel { booking.hotel }
    booking_folio { association(:booking_folio, booking: booking, hotel: hotel) }
    transaction_code do
      hotel.transaction_codes.find_by(system_key: "security_deposit") ||
        association(:transaction_code,
          hotel: hotel,
          system_key: "security_deposit",
          code: "SECDEP",
          name: "Security Deposit",
          kind: "payment",
          category: "security_deposit",
          gl_account_code: "2030",
          system_required: true)
    end
    hold_type { "security" }
    status { "held" }
    amount { 100.0 }
    currency { "MYR" }
    payment_method { "cash" }
  end
end

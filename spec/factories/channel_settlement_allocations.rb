# frozen_string_literal: true

FactoryBot.define do
  factory :channel_settlement_allocation do
    association :channel_settlement
    booking { association(:booking, hotel: channel_settlement.hotel) }
    transient do
      ota_billing_party do
        association(
          :booking_billing_party,
          booking: booking,
          hotel: booking.hotel,
          party_kind: "ota",
          booking_source: channel_settlement.booking_source,
          booking_guest: nil,
          hotel_corporate_account: nil
        )
      end
    end
    booking_folio do
      association(
        :booking_folio,
        booking: booking,
        hotel: booking.hotel,
        folio_type: "external",
        payer_type: "ota",
        is_primary: false,
        booking_billing_party: ota_billing_party,
        hotel_corporate_account: nil
      )
    end
    currency { channel_settlement.currency }
    gross_amount { 100 }
    commission_amount { 10 }
    expected_net_amount { 90 }
  end
end

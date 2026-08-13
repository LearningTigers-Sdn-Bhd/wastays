# frozen_string_literal: true

FactoryBot.define do
  factory :channel_settlement_receipt_allocation do
    association :channel_settlement_allocation
    channel_settlement_receipt do
      allocation = channel_settlement_allocation
      association(
        :channel_settlement_receipt,
        hotel: allocation.channel_settlement.hotel,
        booking_source: allocation.channel_settlement.booking_source,
        currency: allocation.currency
      )
    end
    currency { channel_settlement_allocation.currency }
    amount { channel_settlement_allocation.expected_net_amount }
  end
end

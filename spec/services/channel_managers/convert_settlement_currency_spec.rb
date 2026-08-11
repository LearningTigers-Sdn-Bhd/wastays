# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelManagers::ConvertSettlementCurrency do
  it "returns a failure when no managed rate exists" do
    hotel = create(:hotel, default_currency: "MYR")
    settlement = create(:channel_settlement, hotel: hotel, currency: "USD")

    result = described_class.call(amount: 10, settlement: settlement, target_currency: "EUR")

    expect(result).not_to be_success
    expect(result.error).to include("Missing exchange rate")
    expect(settlement.reload.currency).to eq("USD")
  end
end

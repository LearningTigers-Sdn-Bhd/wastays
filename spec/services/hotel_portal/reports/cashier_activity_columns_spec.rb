# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::CashierActivityColumns do
  it "normalizes columns in canonical order and exposes the compact defaults" do
    expect(described_class.normalize(%w[amount stale date_time])).to eq(%w[date_time amount])
    expect(described_class::DEFAULT_KEYS).to eq(
      %w[date_time reservation guest_details handling payment_mode stage received_by currency amount]
    )
    expect(described_class.selected(%w[guest_details]).first.export_labels).to eq([ "Guest", "Room" ])
  end
end

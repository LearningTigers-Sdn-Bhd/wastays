# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::CashierActivityColumns do
  it "normalizes columns in canonical order and exposes the compact defaults" do
    expect(described_class.normalize(%w[amount stale date_time])).to eq(%w[date_time amount])
    expect(described_class::DEFAULT_KEYS).to eq(
      %w[date_time booking_number guest_details handling payment_mode stage received_by currency amount]
    )
    expect(described_class.selected(%w[guest_details]).first.export_labels).to eq([ "Guest", "Room" ])
  end

  it "offers separate date and time columns that are off by default" do
    expect(described_class.normalize(%w[time date date_time])).to eq(%w[date_time date time])
    expect(described_class::DEFAULT_KEYS).not_to include("date", "time")
    expect(described_class.selected(%w[date time]).map(&:export_labels)).to eq([ [ "Date" ], [ "Time" ] ])
  end

  it "defaults to the booking number and keeps the wider booking columns optional" do
    expect(described_class.normalize(%w[confirmation_code booking_number reservation])).to eq(
      %w[reservation booking_number confirmation_code]
    )
    expect(described_class::DEFAULT_KEYS).to include("booking_number")
    expect(described_class::DEFAULT_KEYS).not_to include("reservation", "confirmation_code")
    expect(described_class.selected(%w[booking_number confirmation_code]).map(&:export_labels)).to eq(
      [ [ "Booking No." ], [ "Confirmation Code" ] ]
    )
  end
end

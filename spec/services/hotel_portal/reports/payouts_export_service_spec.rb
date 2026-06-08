# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::PayoutsExportService do
  let(:hotel) { instance_double(Hotel, name: "Sample Hotel") }

  it "generates upcoming csv/xls/pdf" do
    booking = instance_double(Booking, confirmation_token: "WS-ABC", checked_out_at: Time.zone.local(2026, 5, 7, 10, 0), net_amount: 120.to_d, payout_status: "pending")
    service = described_class.new(hotel: hotel, active_tab: "upcoming", upcoming_bookings: [ booking ], upcoming_payout_amount: 120, processing_batches: [], payout_history: [])

    expect(service.generate_csv).to include("Booking Ref,Checked Out At,Status,Net Amount")
    expect(service.generate_xls).to include('Worksheet ss:Name="Payouts"')
    expect(service.generate_pdf).to start_with("%PDF")
  end

  it "generates paid csv" do
    batch = instance_double(PayoutBatch, period_start: Date.new(2026, 5, 1), period_end: Date.new(2026, 5, 7), payout_at: Date.new(2026, 5, 8), payout_reference: "PO-1", amount: 550.to_d, status: "paid")
    service = described_class.new(hotel: hotel, active_tab: "paid", upcoming_bookings: [], upcoming_payout_amount: 0, processing_batches: [], payout_history: [ batch ])

    expect(service.generate_csv).to include("Period,Settled At,Status,Reference,Net Amount")
  end
end

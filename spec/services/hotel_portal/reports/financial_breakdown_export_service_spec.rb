# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::FinancialBreakdownExportService do
  let(:hotel) { instance_double(Hotel, name: "Sample Hotel") }
  let(:booking) do
    instance_double(
      Booking,
      confirmation_token: "WS-ABC",
      guest_name: "Guest A",
      status: "confirmed",
      check_in: Date.new(2026, 5, 6),
      check_out: Date.new(2026, 5, 7),
      total_amount: 300.to_d,
      margin_amount: 30.to_d,
      net_amount: 270.to_d,
      currency: "MYR",
      booking_folio: nil
    )
  end
  let(:service) do
    described_class.new(bookings: [ booking ], hotel: hotel, start_date: Date.new(2026, 5, 6), end_date: Date.new(2026, 5, 7))
  end

  it "generates csv" do
    expect(service.generate_csv).to include("Booking Ref,Guest Name,Status")
  end

  it "generates xls" do
    expect(service.generate_xls).to include('Worksheet ss:Name="Financial Breakdown"')
  end

  it "generates pdf" do
    expect(service.generate_pdf).to start_with("%PDF")
  end
end

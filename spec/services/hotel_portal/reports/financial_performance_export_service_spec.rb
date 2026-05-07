# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::FinancialPerformanceExportService do
  let(:hotel) { instance_double(Hotel, name: "Sample Hotel") }
  let(:daily_data) do
    {
      Date.new(2026, 5, 6) => { booking_count: 2, gross: 400.to_d, margin: 40.to_d, net: 360.to_d }
    }
  end
  let(:service) do
    described_class.new(
      hotel: hotel,
      start_date: Date.new(2026, 5, 6),
      end_date: Date.new(2026, 5, 7),
      total_gross: 400,
      total_margin: 40,
      total_net: 360,
      booking_count: 2,
      daily_data: daily_data
    )
  end

  it "generates csv" do
    csv = service.generate_csv
    expect(csv).to include("Date,Bookings,Gross,Margin,Net")
    expect(csv).to include("2026-05-06,2,400.00,40.00,360.00")
  end

  it "generates xls" do
    xls = service.generate_xls
    expect(xls).to include('Worksheet ss:Name="Summary"')
    expect(xls).to include('Worksheet ss:Name="Daily Performance"')
  end

  it "generates pdf" do
    pdf = service.generate_pdf
    expect(pdf).to start_with("%PDF")
  end
end

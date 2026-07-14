# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::DailyRevenueCsvExportService do
  it "generates csv" do
    report = instance_double(
      HotelPortal::Reports::DailyRevenueReport::Result,
      rows: [
        {
          date: Date.new(2026, 5, 6),
          booking_count: 2,
          accommodation: 400.to_d,
          other_charges: 5.to_d,
          tax: 10.to_d,
          total_charges: 415.to_d,
          discount: 15.to_d,
          gateway_payment: 200.to_d,
          cash_payment: 100.to_d,
          booking_payment: 50.to_d,
          agent_bank_transfer: 30.to_d,
          corporate_bank_transfer: 12.to_d,
          refund: 25.to_d,
          net_amount: 325.to_d
        }
      ]
    )

    csv = described_class.new(report: report).generate
    expect(csv).to include("Date,Bookings,Accommodation,Other Charges,Tax,Total Charges,Discount,Online,Cash,Deposit,Agent Transfer,Corporate Transfer,Refund,Net")
    expect(csv).to include("2026-05-06,2,400.00,5.00,10.00,415.00,15.00,200.00,100.00,50.00,30.00,12.00,25.00,325.00")
  end
end

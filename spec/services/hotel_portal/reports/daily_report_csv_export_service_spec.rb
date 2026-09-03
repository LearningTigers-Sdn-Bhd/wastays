# frozen_string_literal: true

require "rails_helper"
require "csv"

RSpec.describe HotelPortal::Reports::DailyReportCsvExportService do
  let(:date) { Date.new(2026, 7, 21) }
  let(:revenue_totals) do
    {
      booking_count: 1,
      accommodation: 480.to_d,
      other_charges: 0.to_d,
      tax: 38.40.to_d,
      total_charges: 518.40.to_d,
      adjustments: -20.to_d,
      net_revenue: 498.40.to_d
    }
  end
  let(:revenue_row) { revenue_totals.merge(date: date) }
  let(:source_row) { revenue_totals.merge(source: "Direct") }
  let(:revenue_report) do
    HotelPortal::Reports::DailyRevenueReport::Result.new(
      start_date: date,
      end_date: date,
      totals: revenue_totals,
      rows: [ revenue_row ],
      source_rows: [ source_row ]
    )
  end
  let(:cashier_report) do
    HotelPortal::Reports::CashierSalesReport::Result.new(
      start_date: date,
      end_date: date,
      totals: {
        movement_count: 1,
        total_collected: 100.to_d,
        total_refunded: 0.to_d,
        net_cash: 100.to_d
      },
      cash_transactions: [],
      non_cash_transactions: [],
      non_cash_totals: { movement_count: 0, total_collected: 0.to_d, total_refunded: 0.to_d, net_cash: 0.to_d },
      mode_by_transaction_id: {},
      section_by_transaction_id: {},
      mode_order: [],
      mode_summary_rows: [],
      mode_totals: [],
      currency_summary_rows: [],
      grand_total: { amount_in: 100.to_d, amount_out: 0.to_d, balance: 100.to_d }
    )
  end
  let(:charge_row) do
    instance_double(
      HotelPortal::Reports::DailyReportChargeRegister::Row,
      posting_date: date,
      transaction_time: Time.zone.local(2026, 7, 21, 9, 26),
      service_name: "Room Revenue",
      transaction_code: "ROOM",
      booking_reference: "RES-1001",
      folio_number: "ACR-1001/1",
      guest_name: "Sofia Lim",
      room_number: "G01",
      room_type_name: "Garden Chalet",
      relationship_status: "Original",
      signed_amount: 480.to_d,
      tax_amount: 38.40.to_d,
      total_amount: 518.40.to_d,
      currency: "MYR"
    )
  end

  def generate(tab, charge_register: [])
    described_class.new(
      tab: tab,
      revenue_report: revenue_report,
      cashier_report: cashier_report,
      charge_register: charge_register
    ).generate
  end

  it "exports the overview metrics only" do
    csv = generate("overview")

    expect(csv).to start_with(described_class::BOM)
    expect(csv).to include(
      "Revenue (Accrual),Net Revenue,498.40,MYR",
      "Cashier Activity (Cash Flow),Net Cash,100.00,MYR"
    )
    expect(csv).not_to include("Daily Breakdown", "Cashier Summary")
  end

  it "exports revenue analysis and the Revenue Register" do
    csv = generate("revenue", charge_register: [ charge_row ])

    expect(csv).to include("Daily Breakdown", "Revenue by Source", "Revenue Register")
    expect(csv).to include(HotelPortal::Reports::DailyRevenueTransactionsCsvExportService::HEADERS.to_csv.strip)
    expect(csv).to include("G01,Garden Chalet,Original,480.00,38.40,518.40,MYR")
    expect(csv).not_to include("Cashier Summary")
  end

  it "exports cashier lists and summaries" do
    booking = create(:booking, guest_name: "Cash Guest")
    folio = create(:booking_folio, booking: booking, hotel: booking.hotel)
    payment = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "payment",
      category: "cash",
      amount: 100,
      posting_date: date,
      description: "Front desk cash"
    )
    cashier_report.cash_transactions = [ payment ]
    cashier_report.mode_by_transaction_id = { payment.id => "Cash Payment" }
    cashier_report.section_by_transaction_id = { payment.id => "Settlement" }

    csv = generate("cashier")

    expect(csv).to include("Cashier Activity", "Cashier Summary", "Currency Summary")
    expect(csv).to include("Cash Guest", "Cash Payment", "Front desk cash", "MYR,100.00")
    expect(csv).not_to include("Daily Breakdown", "Revenue Register")
  end
end

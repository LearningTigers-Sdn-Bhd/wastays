# frozen_string_literal: true

require "rails_helper"
require "pdf-reader"

RSpec.describe HotelPortal::Reports::DailyReportPdfExportService do
  let(:hotel) { create(:hotel) }
  let(:start_date) { Date.new(2026, 7, 20) }
  let(:end_date) { Date.new(2026, 7, 20) }

  it "scopes sections to the selected tab" do
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, booking: booking, hotel: hotel, invoice_number: 20260721)
    code = create(:transaction_code, hotel: hotel, code: "CHARTER_BOAT", name: "Charter Boat", kind: "charge", category: "other")
    create(:folio_transaction, booking_folio: folio, transaction_code: code, category: "other", amount: 200, posting_date: start_date)
    advance_payment = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "payment",
      category: "booking_payment",
      amount: 200,
      posting_date: start_date,
      description: "Advance receipt",
      user: nil,
      metadata: { payment_transaction_id: 42, posting_source: "gateway_payment" }
    )
    uninvoiced_booking = create(:booking, hotel: hotel)
    uninvoiced_folio = create(:booking_folio, booking: uninvoiced_booking, hotel: hotel)
    create(
      :folio_transaction,
      booking_folio: uninvoiced_folio,
      transaction_type: "payment",
      category: "cash",
      amount: 50,
      posting_date: start_date,
      description: "Uninvoiced receipt"
    )

    revenue_report = HotelPortal::Reports::DailyRevenueReport.new(hotel: hotel, start_date: start_date, end_date: end_date).call
    cashier_report = HotelPortal::Reports::CashierSalesReport.new(hotel: hotel, start_date: start_date, end_date: end_date).call
    charge_register = HotelPortal::Reports::DailyRevenueTransactionQuery.new(
      hotel: hotel, start_date: start_date, end_date: end_date, transaction_types: %w[charge adjustment]
    ).call
    pdf_service = described_class.new(
      hotel: hotel,
      tab: "cashier",
      revenue_report: revenue_report,
      cashier_report: cashier_report,
      charge_register: charge_register
    )
    cashier_row = pdf_service.send(:cashier_transaction_row, advance_payment)
    expect(cashier_row.size).to eq(9)
    expect(cashier_row[3]).to eq(folio.folio_reference_display)
    expect(cashier_row[4]).to eq("20260721")

    text_for = lambda do |tab|
      pdf = described_class.new(hotel: hotel, tab: tab, revenue_report: revenue_report, cashier_report: cashier_report, charge_register: charge_register).generate
      PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join("\n")
    end

    overview = text_for.call("overview")
    revenue = text_for.call("revenue")
    cashier = text_for.call("cashier")

    expect(overview).to include("Revenue (Accrual)", "Cashier Sales (Cash Flow)", "Net Revenue", "Net Cash")
    expect(overview).not_to include("Daily Breakdown", "Cashier Summary")
    expect(overview).to include("Overview", "Page 1 of")

    expect(revenue).to include(
      "Revenue", "Revenue Summary", "Daily Breakdown", "Revenue by Source", "Charge Register",
      "Charter Boat", "Adjustments", "Net Revenue", "Total", "Page 1 of"
    )
    expect(revenue).not_to include("Cashier Summary", "Advance")

    expect(cashier).to include(
      "Cashier Sales", "Cashier Sales Summary", "Advance", "Settlement",
      "Cashier Summary", "Currency Summary", "Grand Total", "Page 1 of"
    )
    expect(cashier).not_to include("Daily Breakdown", "Charge Register")
    expect(cashier).to include(
      "Date & Time", "Reservation", "Guest Details", "Folio", "Invoice",
      "Payment Mode", "Received By", "Remarks", "Amount",
      "Room —", "20260721", "—",
      "Advance receipt", "Uninvoiced receipt", "Payment Gateway"
    )
    expect(cashier).not_to include("Folio / Invoice", "Guest Room Folio Invoice")
    expect(cashier).not_to include("Room #", "Res. #", "Bill #")
  end
end

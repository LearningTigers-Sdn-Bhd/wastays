# frozen_string_literal: true

require "rails_helper"
require "zip"

RSpec.describe HotelPortal::Reports::DailyReportExcelExportService do
  let(:hotel) { create(:hotel) }
  let(:start_date) { Date.new(2026, 7, 20) }
  let(:end_date) { Date.new(2026, 7, 20) }

  def workbook_entries(content)
    entries = {}
    Zip::File.open_buffer(StringIO.new(content)) do |archive|
      archive.each { |entry| entries[entry.name] = entry.get_input_stream.read }
    end
    entries
  end

  def sheet_names(entries)
    entries.fetch("xl/workbook.xml").scan(/<sheet[^>]+name="([^"]+)"/).flatten
  end

  it "generates tab-scoped xlsx worksheets with analytical spreadsheet features" do
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, booking: booking, hotel: hotel, invoice_number: 20260720)
    code = create(:transaction_code, hotel: hotel, code: "ISLAND_HOP", name: "Island Hopping", kind: "charge", category: "other")
    create(:folio_transaction, booking_folio: folio, transaction_code: code, category: "other", amount: 150, posting_date: start_date)
    cashier = create(:user, name: "Aisha Cashier")
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 150, posting_date: start_date, description: "Paid at front desk", user: cashier)
    create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "payment",
      category: "booking_payment",
      amount: 50,
      posting_date: start_date,
      description: "Online deposit",
      user: nil,
      metadata: { payment_transaction_id: 42, posting_source: "gateway_payment" }
    )

    revenue_report = HotelPortal::Reports::DailyRevenueReport.new(hotel: hotel, start_date: start_date, end_date: end_date).call
    cashier_report = HotelPortal::Reports::CashierSalesReport.new(hotel: hotel, start_date: start_date, end_date: end_date).call
    charge_register = HotelPortal::Reports::DailyRevenueTransactionQuery.new(
      hotel: hotel, start_date: start_date, end_date: end_date, transaction_types: %w[charge adjustment]
    ).call

    generate = lambda do |tab|
      described_class.new(
        hotel: hotel,
        tab: tab,
        revenue_report: revenue_report,
        cashier_report: cashier_report,
        charge_register: charge_register
      ).generate
    end

    overview = generate.call("overview")
    revenue = generate.call("revenue")
    cashier_content = generate.call("cashier")

    expect(overview).to start_with("PK")
    expect(revenue).to start_with("PK")
    expect(cashier_content).to start_with("PK")

    overview_entries = workbook_entries(overview)
    revenue_entries = workbook_entries(revenue)
    cashier_entries = workbook_entries(cashier_content)

    expect(sheet_names(overview_entries)).to eq([ "Overview" ])
    expect(sheet_names(revenue_entries)).to eq([ "Daily Breakdown", "Revenue by Source", "Charge Register" ])
    expect(sheet_names(cashier_entries)).to eq([ "Advance", "Settlement", "Cashier Summary", "Currency Summary" ])

    revenue_xml = revenue_entries.values_at(*revenue_entries.keys.grep(%r{xl/worksheets/sheet\d+\.xml})).join
    cashier_xml = cashier_entries.values_at(*cashier_entries.keys.grep(%r{xl/worksheets/sheet\d+\.xml})).join
    workbook_text = (revenue_entries.values + cashier_entries.values).join

    expect(revenue_xml).to include("<autoFilter", "state=\"frozen\"")
    expect(cashier_xml).to include("<autoFilter", "state=\"frozen\"")
    expect(revenue_entries.fetch("xl/styles.xml")).to include('<sz val="10"/>')
    expect(revenue_xml).to include('zoomScale="100"')
    expect(revenue_xml).to match(/<row[^>]+ht="20"/)
    expect(workbook_text).to include(
      "Daily Report", "Island Hopping", "Currency", "Amount",
      "Paid at front desk", "Aisha Cashier", "Online deposit", "Payment Gateway"
    )
    expect(cashier_xml).to match(/<c[^>]*r="[A-Z]+\d+"[^>]*><v>150(?:\.0)?<\/v><\/c>/)
  end
end

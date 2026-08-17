# frozen_string_literal: true

require "rails_helper"
require "pdf-reader"

RSpec.describe HotelPortal::Reports::DailyReportPdfExportService do
  let(:hotel) { create(:hotel) }
  let(:start_date) { Date.new(2026, 7, 20) }
  let(:end_date) { Date.new(2026, 7, 20) }

  it "scopes sections to the selected tab" do
    booking = create(:booking, hotel: hotel)
    room_type = create(:room_type, hotel: hotel, name: "Deluxe King")
    booking_room = create(:booking_room, booking: booking, room_type: room_type, room_number: "G01")
    folio = create(:booking_folio, booking: booking, booking_room: booking_room, hotel: hotel, invoice_number: 20260721)
    code = create(:transaction_code, hotel: hotel, code: "CHARTER_BOAT", name: "Charter Boat", kind: "charge", category: "other")
    create(:folio_transaction, booking_folio: folio, transaction_code: code, category: "other", amount: 200, posting_date: start_date)
    room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    sst_code = hotel.transaction_codes.find_by!(system_key: "sst_tax")
    room_charge = create(:folio_transaction, booking_folio: folio, transaction_code: room_code,
      category: "accommodation", amount: 480, posting_date: start_date)
    create(:folio_transaction, booking_folio: folio, transaction_code: sst_code,
      category: "tax", amount: 38.40, posting_date: start_date,
      metadata: { parent_folio_transaction_id: room_charge.id, tax_line: { type: "sst" } })
    create(:folio_transaction, booking_folio: folio, transaction_type: "adjustment",
      category: "discount", amount: -20, posting_date: start_date)
    bank_code = hotel.transaction_codes.find_by!(system_key: "bank_payment")
    advance_payment = create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "payment",
      category: "booking_payment",
      amount: 200,
      posting_date: start_date,
      description: "Advance receipt",
      user: nil,
      transaction_code: bank_code
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
    charge_register = HotelPortal::Reports::DailyReportChargeRegister.new(
      transactions: HotelPortal::Reports::DailyRevenueTransactionQuery.new(
        hotel: hotel, start_date: start_date, end_date: end_date,
        transaction_types: %w[charge adjustment]
      ).call
    ).call.rows
    pdf_service = described_class.new(
      hotel: hotel,
      tab: "cashier",
      revenue_report: revenue_report,
      cashier_report: cashier_report,
      prepared_by: "Aina Salleh",
      charge_register: charge_register
    )
    cashier_row = pdf_service.send(:cashier_transaction_row, advance_payment)
    expect(cashier_row.size).to eq(9)
    expect(cashier_row[3]).to eq(folio.folio_reference_display)
    expect(cashier_row[4]).to eq("20260721")

    charge_register_tables = []
    text_for = lambda do |tab|
      service = described_class.new(
        hotel: hotel,
        tab: tab,
        revenue_report: revenue_report,
        cashier_report: cashier_report,
        prepared_by: "Aina Salleh",
        charge_register: charge_register
      )
      if tab == "revenue"
        allow(service).to receive(:draw_data_table).and_wrap_original do |method, pdf, headers, rows, **options|
          charge_register_tables << { headers: headers, rows: rows, **options } if headers.include?("Service / Code")
          method.call(pdf, headers, rows, **options)
        end
      end

      pdf = service.generate
      PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join("\n")
    end

    overview = text_for.call("overview")
    revenue = text_for.call("revenue")
    cashier = text_for.call("cashier")

    expect(overview).to include("Revenue (Accrual)", "Cashier Sales (Cash Flow)", "NET REVENUE", "NET CASH")
    expect(overview).not_to include("Daily Breakdown", "Cashier Summary")
    expect(overview).to include(
      "Daily Report", "Overview", "PERIOD", "GENERATED", "PREPARED BY", "Aina Salleh",
      "Confidential", "Page 1 of"
    )

    expect(revenue).to include(
      "Revenue", "Revenue Summary", "Daily Breakdown", "Revenue by Source", "Revenue Register",
      "Charter Boat", "Adjustments", "Net Revenue", "Total", "Page 1 of"
    )
    # Mixed case above is the table header; the stat strip carries the same words upcased,
    # so assert both rather than letting one stand in for the other.
    expect(revenue).to include("BOOKINGS ENGAGED", "TOTAL CHARGES", "NET REVENUE")
    expect(revenue).not_to include("Cashier Summary", "Advance")
    register_table = charge_register_tables.sole
    expect(register_table).to include(
      headers: [ "Date & Time", "Service / Code", "Booking / Folio", "Guest / Room Details", "Status", "Base Amount", "Tax", "Total Amount" ],
      rows: a_kind_of(Array),
      numeric_columns: [ 5, 6, 7 ],
      total_row: 4,
      column_widths: [ 65, 125, 125, 115, 60, 84, 78, 90 ]
    )
    register_rows = register_table.fetch(:rows)
    room_row = register_rows.find { |row| row[5] == "MYR 480.00" }
    expect(room_row).to include("MYR 480.00", "MYR 38.40", "MYR 518.40")
    negative_row_index = register_rows.index { |row| row[5] == "MYR -20.00" }
    expect(register_table.fetch(:negative_cells)).to include([ negative_row_index, 5 ], [ negative_row_index, 7 ])
    expect(register_rows.last).to eq([ "Total", nil, nil, nil, nil, "MYR 660.00", "MYR 38.40", "MYR 698.40" ])
    expect(register_rows.flatten.compact.join(" ")).not_to include("TAX_SST")
    expect(register_rows.flatten.compact.join(" ")).to include("G01 · Deluxe King")

    expect(cashier).to include(
      "Cashier Sales", "Cashier Sales Summary", "Advance", "Settlement",
      "Cashier Summary", "Currency Summary", "Grand Total", "Page 1 of"
    )
    expect(cashier).not_to include("Daily Breakdown", "Revenue Register")
    expect(cashier).to include(
      "Date & Time", "Reservation", "Guest Details", "Folio", "Invoice",
      "Payment Mode", "Received By", "Remarks", "Amount",
      "Room —", "20260721", "—",
      "Advance receipt", "Uninvoiced receipt", "Bank Transfer Payment"
    )
    expect(cashier).not_to include("Folio / Invoice", "Guest Room Folio Invoice")
    expect(cashier).not_to include("Room #", "Res. #", "Bill #")
  end
end

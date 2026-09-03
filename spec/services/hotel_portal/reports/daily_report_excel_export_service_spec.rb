# frozen_string_literal: true

require "rails_helper"
require "zip"
require "nokogiri"

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

  def worksheet_xml(entries, worksheet_name)
    workbook = Nokogiri::XML(entries.fetch("xl/workbook.xml"))
    workbook.remove_namespaces!
    relationship_id = workbook.xpath("//sheet").find { |sheet| sheet["name"] == worksheet_name }["id"]

    relationships = Nokogiri::XML(entries.fetch("xl/_rels/workbook.xml.rels"))
    relationships.remove_namespaces!
    target = relationships.xpath("//Relationship").find { |relationship| relationship["Id"] == relationship_id }["Target"]

    entries.fetch("xl/#{target.delete_prefix('/')}")
  end

  def worksheet_rows(entries, worksheet)
    shared_strings = if (content = entries["xl/sharedStrings.xml"])
      Nokogiri::XML(content).xpath("//xmlns:si").map { |string| string.xpath(".//xmlns:t").map(&:text).join }
    else
      []
    end
    document = Nokogiri::XML(worksheet)

    document.xpath("//xmlns:sheetData/xmlns:row").map do |row|
      row.xpath("./xmlns:c").each_with_object({}) do |cell, values|
        reference = cell["r"].sub(/\d+\z/, "")
        value = cell.at_xpath("./xmlns:is/xmlns:t")&.text || cell.at_xpath("./xmlns:v")&.text
        value = shared_strings.fetch(value.to_i) if cell["t"] == "s"
        values[reference] = { value: value, style: cell["s"], type: cell["t"] }
      end
    end
  end

  def number_format(entries, style_id)
    styles = Nokogiri::XML(entries.fetch("xl/styles.xml"))
    format_id = styles.xpath("//xmlns:cellXfs/xmlns:xf")[style_id.to_i]["numFmtId"]

    styles.at_xpath("//xmlns:numFmt[@numFmtId='#{format_id}']")&.[]("formatCode")
  end

  def font_size(entries, style_id)
    styles = Nokogiri::XML(entries.fetch("xl/styles.xml"))
    font_id = styles.xpath("//xmlns:cellXfs/xmlns:xf")[style_id.to_i]["fontId"]
    styles.xpath("//xmlns:fonts/xmlns:font")[font_id.to_i].at_xpath("./xmlns:sz")["val"].to_f
  end

  it "generates tab-scoped xlsx worksheets with analytical spreadsheet features" do
    booking = create(:booking, hotel: hotel)
    room_type = create(:room_type, hotel: hotel, name: "Deluxe King")
    booking_room = create(:booking_room, booking: booking, room_type: room_type, room_number: "G01")
    folio = create(:booking_folio, booking: booking, booking_room: booking_room, hotel: hotel, invoice_number: 20260720)
    room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
    sst_code = hotel.transaction_codes.find_by!(system_key: "sst_tax")
    room_charge = create(:folio_transaction, booking_folio: folio, transaction_code: room_code,
      category: "accommodation", amount: 480, posting_date: start_date)
    create(:folio_transaction, booking_folio: folio, transaction_code: sst_code,
      category: "tax", amount: 38.40, posting_date: start_date,
      metadata: { parent_folio_transaction_id: room_charge.id, tax_line: { type: "sst" } })
    create(:folio_transaction, booking_folio: folio, transaction_type: "adjustment",
      category: "discount", amount: -20, posting_date: start_date)
    cashier = create(:user, name: "Aisha Cashier")
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 150, posting_date: start_date, description: "Paid at front desk", user: cashier)
    bank_code = hotel.transaction_codes.find_by!(system_key: "bank_payment")
    create(
      :folio_transaction,
      booking_folio: folio,
      transaction_type: "payment",
      category: "booking_payment",
      amount: 50,
      posting_date: start_date,
      description: "Advance deposit",
      user: nil,
      transaction_code: bank_code
    )

    revenue_report = HotelPortal::Reports::DailyRevenueReport.new(hotel: hotel, start_date: start_date, end_date: end_date).call
    cashier_report = HotelPortal::Reports::CashierSalesReport.new(hotel: hotel, start_date: start_date, end_date: end_date).call
    charge_register = HotelPortal::Reports::DailyReportChargeRegister.new(
      transactions: HotelPortal::Reports::DailyRevenueTransactionQuery.new(
        hotel: hotel, start_date: start_date, end_date: end_date, transaction_types: %w[charge adjustment]
      ).call
    ).call.rows

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
    overview_rows = worksheet_rows(overview_entries, worksheet_xml(overview_entries, "Overview"))
    metadata_cell = overview_rows.find { |row| row["A"]&.fetch(:value)&.start_with?("Reporting period:") }.fetch("A")
    section_cell = overview_rows.find { |row| row["A"]&.fetch(:value) == "Revenue (Accrual)" }.fetch("A")
    metric_header = overview_rows.find { |row| row["A"]&.fetch(:value) == "Metric" }.fetch("A")
    kpi_value = overview_rows.find { |row| row["A"]&.fetch(:value) == "Total Charges" }.fetch("B")

    expect(sheet_names(overview_entries)).to eq([ "Overview" ])
    expect(sheet_names(revenue_entries)).to eq([ "Daily Breakdown", "Revenue by Source", "Revenue Register" ])
    expect(sheet_names(cashier_entries)).to eq([ "Cashier Activity", "Activity By Payment Mode", "Currency Summary" ])
    expect(font_size(overview_entries, metadata_cell.fetch(:style))).to eq(11)
    expect(font_size(overview_entries, section_cell.fetch(:style))).to eq(12)
    expect(font_size(overview_entries, metric_header.fetch(:style))).to eq(11)
    expect(font_size(overview_entries, kpi_value.fetch(:style))).to eq(13)

    revenue_xml = revenue_entries.values_at(*revenue_entries.keys.grep(%r{xl/worksheets/sheet\d+\.xml})).join
    cashier_xml = cashier_entries.values_at(*cashier_entries.keys.grep(%r{xl/worksheets/sheet\d+\.xml})).join
    workbook_text = (revenue_entries.values + cashier_entries.values).join
    charge_register_xml = worksheet_xml(revenue_entries, "Revenue Register")
    charge_register_document = Nokogiri::XML(charge_register_xml)
    charge_register_rows = worksheet_rows(revenue_entries, charge_register_xml)
    charge_register_header = charge_register_rows.find { |row| row["A"]&.fetch(:value) == "Posting Date" }
    charge_register_data = charge_register_rows.find { |row| row["K"]&.fetch(:value).to_d == 480.to_d }
    charge_register_negative = charge_register_rows.find { |row| row["K"]&.fetch(:value).to_d == -20.to_d }
    charge_register_total = charge_register_rows.find { |row| row["A"]&.fetch(:value) == "Total" }

    expect(revenue_xml).to include("<autoFilter", "state=\"frozen\"")
    expect(cashier_xml).to include("<autoFilter", "state=\"frozen\"")
    expect(revenue_entries.fetch("xl/styles.xml")).to include('<sz val="11"/>')
    expect(revenue_xml).to include('zoomScale="100"')
    expect(revenue_xml).to match(/<row[^>]+ht="22"/)
    expect(workbook_text).to include(
      "Daily Report", "Room Revenue", "Currency", "Amount", "Tax",
      "Paid at front desk", "Aisha Cashier", "Advance deposit", "Bank Transfer Payment"
    )
    expect(charge_register_header.values.map { |cell| cell[:value] }).to eq(HotelPortal::Reports::DailyRevenueTransactionsCsvExportService::HEADERS)
    expect(charge_register_document.xpath("//xmlns:cols/xmlns:col").sum { |column| column["max"].to_i - column["min"].to_i + 1 }).to eq(14)
    expect(charge_register_document.xpath("//xmlns:mergeCell").map { |cell| cell["ref"] }).to include("A1:N1")
    expect(charge_register_data.fetch("I")).to include(value: "Deluxe King")
    expect(charge_register_data.fetch("K")).to include(value: "480.0", type: "n")
    expect(charge_register_data.fetch("L")).to include(value: "38.4", type: "n")
    expect(charge_register_data.fetch("M")).to include(value: "518.4", type: "n")
    expect(charge_register_negative.fetch("K")).to include(value: "-20.0", type: "n")
    expect(number_format(revenue_entries, charge_register_negative.fetch("K").fetch(:style))).to eq("#,##0.00;[Red]-#,##0.00")
    expect(charge_register_total.fetch("K")).to include(value: "460.0", type: "n")
    expect(charge_register_total.fetch("L")).to include(value: "38.4", type: "n")
    expect(charge_register_total.fetch("M")).to include(value: "498.4", type: "n")
    expect(number_format(revenue_entries, charge_register_total.fetch("M").fetch(:style))).to eq("#,##0.00;[Red]-#,##0.00")
    expect(charge_register_xml).not_to include("TAX_SST")
    expect(cashier_xml).to match(/<c[^>]*r="[A-Z]+\d+"[^>]*><v>150(?:\.0)?<\/v><\/c>/)
  end
end

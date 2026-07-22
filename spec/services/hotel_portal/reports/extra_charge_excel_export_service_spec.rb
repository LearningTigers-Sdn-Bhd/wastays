# frozen_string_literal: true

require "rails_helper"
require "zip"
require "nokogiri"

RSpec.describe HotelPortal::Reports::ExtraChargeExcelExportService do
  def workbook_entries(content)
    entries = {}
    Zip::File.open_buffer(StringIO.new(content)) do |archive|
      archive.each { |entry| entries[entry.name] = entry.get_input_stream.read }
    end
    entries
  end

  def sheet_names(entries)
    workbook = Nokogiri::XML(entries.fetch("xl/workbook.xml"))
    workbook.xpath("//xmlns:sheet").map { |sheet| sheet["name"] }
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
        values[reference] = { value: value, style: cell["s"], type: cell["t"] || "n" }
      end
    end
  end

  def font_size(entries, style_id)
    styles = Nokogiri::XML(entries.fetch("xl/styles.xml"))
    font_id = styles.xpath("//xmlns:cellXfs/xmlns:xf")[style_id.to_i]["fontId"]
    styles.xpath("//xmlns:fonts/xmlns:font")[font_id.to_i].at_xpath("./xmlns:sz")["val"].to_f
  end

  def wraps_text?(entries, style_id)
    styles = Nokogiri::XML(entries.fetch("xl/styles.xml"))
    alignment = styles.xpath("//xmlns:cellXfs/xmlns:xf")[style_id.to_i].at_xpath("./xmlns:alignment")

    alignment&.[]("wrapText") == "1"
  end

  def vertical_alignment(entries, style_id)
    styles = Nokogiri::XML(entries.fetch("xl/styles.xml"))
    styles.xpath("//xmlns:cellXfs/xmlns:xf")[style_id.to_i].at_xpath("./xmlns:alignment")&.[]("vertical")
  end

  def report(active_tab: "fb", rows:, totals:)
    double(
      "report",
      start_date: Date.new(2026, 7, 1),
      end_date: Date.new(2026, 7, 2),
      active_tab: active_tab,
      rows: rows,
      totals: totals
    )
  end

  let(:hotel) { double("hotel", name: "The Riverside Hotel", default_currency: "MYR") }
  let(:rows) do
    [
      {
        posting_date: Date.new(2026, 7, 2),
        booking_reference: "BK-001",
        folio_number: "FOL-001",
        guest_name: "Jane Doe",
        description: "Mini bar",
        category: "fb",
        amount: 25
      }
    ]
  end

  it "generates a typed F&B charges XLSX workbook" do
    content = described_class.new(
      hotel: hotel,
      report: report(rows: rows, totals: { transaction_count: 1, total_amount: 25 })
    ).generate

    expect(content).to start_with("PK")
    entries = workbook_entries(content)
    expect(sheet_names(entries)).to eq([ "F&B Charges" ])

    sheet = worksheet_xml(entries, "F&B Charges")
    rows = worksheet_rows(entries, sheet)
    header = rows.find { |row| row["A"]&.fetch(:value) == "Posting Date" }
    detail = rows.find { |row| row["B"]&.fetch(:value) == "BK-001" }
    total = rows.find { |row| row["A"]&.fetch(:value) == "Total" }
    summary_labels = rows.fetch(5)
    summary_values = rows.fetch(6)

    expect(header.values.map { |cell| cell[:value] }).to eq(HotelPortal::Reports::ExtraChargeCsvExportService::HEADERS)
    expect(summary_labels.values_at("A", "E").map { |cell| cell&.fetch(:value) }).to eq([ "Transactions", "Total Amount" ])
    expect(summary_values.fetch("A")).to include(value: "1", type: "n")
    expect(summary_values.fetch("E")).to include(value: "25.0", type: "n")
    expect(summary_values.fetch("H").fetch(:value)).to eq("MYR")
    expect(detail.fetch("A").fetch(:type)).to eq("n")
    expect(detail.fetch("H")).to include(value: "25.0", type: "n")
    expect(total.fetch("H")).to include(value: "25.0", type: "n")
    expect(sheet).to include("<autoFilter", "state=\"frozen\"")
    expect(sheet).not_to include("showGridLines=\"0\"")
    sheet_document = Nokogiri::XML(sheet)
    pane = sheet_document.at_xpath("//xmlns:sheetView/xmlns:pane")
    merges = sheet_document.xpath("//xmlns:mergeCell").map { |cell| cell["ref"] }
    expect(merges).to include("A5:H5", "A6:D6", "E6:H6", "A7:D7", "E7:G7", "A8:H8")
    expect(sheet_document.at_xpath("//xmlns:autoFilter")["ref"]).to eq("A9:H10")
    expect(pane["ySplit"]).to eq("9")
    expect(pane["topLeftCell"]).to eq("A10")
    expect(font_size(entries, detail.fetch("D").fetch(:style))).to eq(11)
  end

  it "uses the non-F&B charge sheet name" do
    content = described_class.new(
      hotel: hotel,
      report: report(active_tab: "non_fb", rows: rows, totals: { transaction_count: 1, total_amount: 25 })
    ).generate

    expect(sheet_names(workbook_entries(content))).to eq([ "Non-F&B Charges" ])
  end

  it "shows an empty state and a zero total" do
    content = described_class.new(
      hotel: hotel,
      report: report(rows: [], totals: { transaction_count: 0, total_amount: 0 })
    ).generate
    entries = workbook_entries(content)
    sheet = worksheet_xml(entries, "F&B Charges")
    worksheet_rows = worksheet_rows(entries, sheet)
    empty_state = worksheet_rows.find { |row| row["A"]&.fetch(:value) == "No extra charge transactions found for this period." }
    total = worksheet_rows.find { |row| row["A"]&.fetch(:value) == "Total" }

    expect(empty_state).to be_present
    expect(total.fetch("H")).to include(value: "0.0", type: "n")
  end

  it "wraps long text columns and gives the detail row sufficient height" do
    long_rows = [
      {
        posting_date: Date.new(2026, 7, 2),
        booking_reference: "BOOKING-#{'REFERENCE-' * 12}END",
        folio_number: "FOLIO-#{'REFERENCE-' * 12}END",
        guest_name: "Guest #{'With A Very Long Name ' * 8}End",
        description: "Description #{'with complete long content ' * 18}END-MARKER",
        category: "category_#{'with_a_long_label_' * 10}end",
        amount: 25
      }
    ]
    content = described_class.new(
      hotel: hotel,
      report: report(rows: long_rows, totals: { transaction_count: 1, total_amount: 25 })
    ).generate
    entries = workbook_entries(content)
    sheet = worksheet_xml(entries, "F&B Charges")
    parsed_rows = worksheet_rows(entries, sheet)
    detail_index = parsed_rows.index { |row| row["B"]&.fetch(:value)&.start_with?("BOOKING-") }
    detail = parsed_rows.fetch(detail_index)
    row_element = Nokogiri::XML(sheet).xpath("//xmlns:sheetData/xmlns:row")[detail_index]
    column_widths = Nokogiri::XML(sheet).xpath("//xmlns:cols/xmlns:col").map { |column| column["width"].to_f }

    long_values = detail.values_at("B", "C", "D", "E", "F").map { |cell| cell.fetch(:value) }
    expect(long_values.map(&:length)).to all(be > 100)
    expect(long_values[3]).to end_with("END-MARKER")
    expect(detail.values_at("B", "C", "D", "E", "F")).to all(satisfy { |cell| wraps_text?(entries, cell.fetch(:style)) })
    expect(detail.values_at("A", "H").map { |cell| vertical_alignment(entries, cell.fetch(:style)) }).to eq([ "top", "top" ])
    expect(row_element["ht"].to_f).to be > 22
    expect(row_element["customHeight"]).to eq("1")
    expect(column_widths.size).to eq(8)
    expect(column_widths.max).to be <= 45
  end
end

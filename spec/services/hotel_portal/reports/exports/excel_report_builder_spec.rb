# frozen_string_literal: true

require "rails_helper"
require "zip"
require "nokogiri"

RSpec.describe HotelPortal::Reports::Exports::ExcelReportBuilder do
  let(:hotel) { double("hotel", name: "Hôtel 東京") }

  def workbook_entries(content)
    Zip::File.open_buffer(StringIO.new(content)).each_with_object({}) do |entry, entries|
      entries[entry.name] = entry.get_input_stream.read
    end
  end

  def number_format_for(entries, cell_reference)
    worksheet = Nokogiri::XML(entries.fetch("xl/worksheets/sheet1.xml"))
    styles = Nokogiri::XML(entries.fetch("xl/styles.xml"))
    style_index = worksheet.at_xpath("//xmlns:c[@r='#{cell_reference}']")["s"].to_i
    number_format_id = styles.xpath("//xmlns:cellXfs/xmlns:xf")[style_index]["numFmtId"]

    styles.at_xpath("//xmlns:numFmt[@numFmtId='#{number_format_id}']")&.[]("formatCode")
  end

  it "builds a typed, readable workbook with shared report structure" do
    content = described_class.new(
      hotel: hotel,
      title: "Contract Report",
      period_label: "22 Jul 2026",
      generated_at: Time.zone.local(2026, 7, 22, 10, 30)
    ).generate do |builder|
      sheet = builder.add_sheet(name: "Contract", widths: [ 14, 24, 16 ])
      builder.add_header(sheet: sheet, subtitle: "Contract")
      builder.add_summary(sheet: sheet, metrics: [ [ "Transactions", 1, nil ], [ "Total", 25.to_d, "MYR" ] ])
      builder.add_table(
        sheet: sheet,
        section_title: "Details",
        headers: [ "Date", "Description", "Amount" ],
        rows: [ [ Date.new(2026, 7, 22), "Dinner", 25.to_d ] ],
        column_types: %i[date text money],
        total_row: [ "Total", nil, 25.to_d ],
        empty_message: "No rows"
      )
    end

    expect(content).to start_with("PK")
    entries = workbook_entries(content)
    worksheet = entries.fetch("xl/worksheets/sheet1.xml")
    styles = entries.fetch("xl/styles.xml")
    workbook_text = entries.values_at("xl/sharedStrings.xml", "xl/worksheets/sheet1.xml")
      .compact.join.force_encoding(Encoding::UTF_8)

    expect(workbook_text).to include("Contract Report", "Hôtel 東京", "22 Jul 2026", "Transactions", "Dinner")
    expect(styles).to include('<sz val="18"/>', '<sz val="13"/>', '<sz val="12"/>', '<sz val="11"/>')
    expect(worksheet).to include("<autoFilter", 'state="frozen"')
    expect(worksheet).not_to include('showGridLines="0"')
    expect(Nokogiri::XML(worksheet).xpath("//xmlns:c[not(@t='s')]/xmlns:v").map(&:text)).to include("25.0")
  end

  it "renders a valid empty-state table" do
    content = described_class.new(hotel: hotel, title: "Empty", period_label: "22 Jul 2026").generate do |builder|
      sheet = builder.add_sheet(name: "Empty", widths: [ 20 ])
      builder.add_header(sheet: sheet)
      builder.add_table(
        sheet: sheet,
        section_title: "Details",
        headers: [ "Value" ],
        rows: [],
        column_types: [ :text ],
        total_row: [ "Total" ],
        empty_message: "No rows"
      )
    end

    expect(workbook_entries(content).values.join).to include("No rows", "Total")
  end

  it "stores identifiers as text and preserves each total column's number format" do
    content = described_class.new(hotel: hotel, title: "Types", period_label: "22 Jul 2026").generate do |builder|
      sheet = builder.add_sheet(name: "Types", widths: [ 18, 12, 14, 14 ])
      builder.add_header(sheet: sheet)
      builder.add_table(
        sheet: sheet,
        section_title: "Details",
        headers: [ "Identifier", "Count", "Occupancy", "Amount" ],
        rows: [ [ "0010", 7, 0.35, 25.to_d ] ],
        column_types: %i[text integer percentage money],
        total_row: [ "TOTAL", 7, 0.35, 25.to_d ],
        empty_message: "No rows"
      )
    end

    entries = workbook_entries(content)
    worksheet = Nokogiri::XML(entries.fetch("xl/worksheets/sheet1.xml"))

    expect(worksheet.at_xpath("//xmlns:c[@r='A7']")["t"]).to eq("s")
    expect(number_format_for(entries, "B8")).to eq("#,##0")
    expect(number_format_for(entries, "C8")).to eq("0.00%")
    expect(number_format_for(entries, "D8")).to eq("#,##0.00;[Red]-#,##0.00")
  end
end

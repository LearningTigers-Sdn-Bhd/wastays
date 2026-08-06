# frozen_string_literal: true

require "rails_helper"
require "pdf-reader"

RSpec.describe HotelPortal::Reports::Exports::PdfReportBuilder do
  let(:hotel) { double("hotel", name: "Hôtel 東京") }

  def extracted_text(content)
    PDF::Reader.new(StringIO.new(content)).pages.map(&:text).join("\n")
  end

  it "builds a branded Unicode report with summary, detail, total, and footer" do
    builder = described_class.new(
      hotel: hotel,
      title: "Contract Report",
      subtitle: "Contract",
      period_label: "22 Jul 2026",
      generated_at: Time.zone.local(2026, 7, 22, 10, 30),
      page_layout: :landscape
    )
    builder.add_header
    builder.add_summary([ [ "Transactions", "1" ], [ "Total Amount", "MYR 25.00" ] ])
    builder.add_table(
      section_title: "Details",
      headers: [ "Guest", "Description", "Amount" ],
      rows: [ [ "测试 Guest", "Dinner", "25.00" ] ],
      numeric_columns: [ 2 ],
      total_row: [ "Total", nil, "25.00" ],
      empty_message: "No rows"
    )

    content = builder.render
    text = extracted_text(content)

    expect(content).to start_with("%PDF")
    expect(text).to include("CONTRACT REPORT", "Contract", "Hôtel 東京", "22 Jul 2026")
    expect(text).to include("Transactions", "Total Amount", "测试 Guest", "Dinner", "Total")
    expect(text).to match(/Page 1 of \d+/)
    expect(PDF::Reader.new(StringIO.new(content)).pages.first.xobjects).not_to be_empty
  end

  it "renders an informative empty state" do
    builder = described_class.new(hotel: hotel, title: "Empty", period_label: "22 Jul 2026")
    builder.add_header
    builder.add_table(
      section_title: "Details",
      headers: [ "Value" ],
      rows: [],
      numeric_columns: [],
      total_row: [ "Total" ],
      empty_message: "No rows"
    )

    expect(extracted_text(builder.render)).to include("No rows", "Total")
  end
end

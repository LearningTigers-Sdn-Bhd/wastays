# frozen_string_literal: true

require "rails_helper"
require "zip"
require "nokogiri"

RSpec.describe HotelPortal::Reports::SimpleExcelReport do
  let(:hotel) { create(:hotel, name: "Kit Test Hotel") }

  let(:exporter_class) do
    Class.new do
      include HotelPortal::Reports::SimpleExcelReport

      def initialize(hotel:)
        @hotel = hotel
      end

      def generate
        build_workbook do
          sheet = add_report_sheet(title: "Sample", column_count: 3, widths: [ 20, 12, 12 ], period_label: "01 Jul 2026")
          add_data_table(
            sheet,
            headers: [ "Name", "Amount", "Tax" ],
            rows: [ [ "Row One", decimal(10), decimal(2) ] ],
            money_columns: [ 1, 2 ],
            total_row: [ "TOTAL", decimal(10), decimal(2) ]
          )
        end
      end
    end
  end

  def workbook_entries(content)
    entries = {}
    Zip::File.open_buffer(StringIO.new(content)) do |archive|
      archive.each { |entry| entries[entry.name] = entry.get_input_stream.read }
    end
    entries
  end

  it "generates a real xlsx workbook with the given sheet and rows" do
    content = exporter_class.new(hotel: hotel).generate
    entries = workbook_entries(content)

    expect(entries.keys).to include("xl/workbook.xml", "[Content_Types].xml")

    sheet_xml = entries.values_at(*entries.keys.grep(%r{xl/worksheets/sheet1\.xml})).first
    shared_strings = Nokogiri::XML(entries.fetch("xl/sharedStrings.xml")).xpath("//xmlns:si").map { |s| s.xpath(".//xmlns:t").map(&:text).join }

    expect(shared_strings).to include("Row One", "TOTAL", "Name", "Amount", "Tax")
    expect(sheet_xml).to include("<sheetData")
  end
end

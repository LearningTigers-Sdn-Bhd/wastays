# frozen_string_literal: true

require "rails_helper"
require "zip"
require "nokogiri"

RSpec.describe HotelPortal::Reports::SstExcelExportService do
  describe "#generate" do
    it "builds an xlsx workbook with SST rows and totals" do
      hotel = create(:hotel, name: "Sample Hotel")
      report = double(
        "report",
        start_date: Date.new(2026, 7, 1),
        end_date: Date.new(2026, 7, 2),
        rows: [
          {
            invoice_number: "INV-001",
            guest_name: "Amira Yusof",
            check_in: Date.new(2026, 7, 1),
            check_out: Date.new(2026, 7, 3),
            taxable_amount: 200,
            sst_amount: 16,
            total_amount: 216
          }
        ],
        totals: { booking_count: 1, taxable_amount: 200, sst_amount: 16, total_amount: 216 }
      )

      content = described_class.new(hotel: hotel, report: report).generate

      entries = {}
      Zip::File.open_buffer(StringIO.new(content)) do |archive|
        archive.each { |entry| entries[entry.name] = entry.get_input_stream.read }
      end
      shared_strings = Nokogiri::XML(entries.fetch("xl/sharedStrings.xml")).xpath("//xmlns:si").map { |s| s.xpath(".//xmlns:t").map(&:text).join }

      expect(shared_strings).to include("INV-001", "Amira Yusof")
      expect(entries.fetch("xl/workbook.xml")).to include("SST")
    end
  end
end

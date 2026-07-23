# frozen_string_literal: true

require "rails_helper"
require "zip"
require "nokogiri"

RSpec.describe HotelPortal::Reports::TourismTaxExcelExportService do
  describe "#generate" do
    it "builds an xlsx workbook with tourism tax rows and totals" do
      hotel = create(:hotel, name: "Sample Hotel")
      report = double(
        "report",
        start_date: Date.new(2026, 7, 1),
        end_date: Date.new(2026, 7, 2),
        rows: [
          {
            guest_name: "Kenji Sato",
            guest_country: "Japan",
            booking_reference: "BK-001",
            check_in: Date.new(2026, 7, 2),
            check_out: Date.new(2026, 7, 4),
            nights: 2,
            tax_due: 20,
            tax_collected: 20,
            collection_status: "Collected"
          }
        ],
        totals: { guest_count: 1, total_due: 20, total_collected: 20 }
      )

      content = described_class.new(hotel: hotel, report: report).generate

      entries = {}
      Zip::File.open_buffer(StringIO.new(content)) do |archive|
        archive.each { |entry| entries[entry.name] = entry.get_input_stream.read }
      end
      shared_strings = Nokogiri::XML(entries.fetch("xl/sharedStrings.xml")).xpath("//xmlns:si").map { |s| s.xpath(".//xmlns:t").map(&:text).join }

      expect(shared_strings).to include("Kenji Sato", "Japan", "BK-001", "Collected")
      expect(entries.fetch("xl/workbook.xml")).to include("Tourism Tax")
    end
  end
end

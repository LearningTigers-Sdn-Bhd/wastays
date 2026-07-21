# frozen_string_literal: true

require "rails_helper"
require "zip"
require "nokogiri"

RSpec.describe HotelPortal::Reports::NonNationalExcelExportService do
  describe "#generate" do
    it "builds an xlsx workbook with non-national guest rows" do
      hotel = create(:hotel, name: "Sample Hotel")
      report = double(
        "report",
        start_date: Date.new(2026, 7, 1),
        end_date: Date.new(2026, 7, 1),
        rows: [
          {
            guest_name: "Kenji Sato",
            guest_country: "Japan",
            date_of_birth: Date.new(1990, 5, 20),
            guest_home_address: "1 Chome, Tokyo",
            check_in: Date.new(2026, 6, 30),
            checked_in_at: Time.zone.local(2026, 6, 30, 15, 45, 0),
            check_out: Date.new(2026, 7, 2)
          }
        ],
        totals: { guest_count: 1, nights: 2 }
      )

      content = described_class.new(hotel: hotel, report: report).generate

      entries = {}
      Zip::File.open_buffer(StringIO.new(content)) do |archive|
        archive.each { |entry| entries[entry.name] = entry.get_input_stream.read }
      end
      shared_strings = Nokogiri::XML(entries.fetch("xl/sharedStrings.xml")).xpath("//xmlns:si").map { |s| s.xpath(".//xmlns:t").map(&:text).join }

      expect(shared_strings).to include("Kenji Sato", "Japan", "1 Chome, Tokyo")
      expect(entries.fetch("xl/workbook.xml")).to include("Non-National")
    end
  end
end

# frozen_string_literal: true

require "rails_helper"
require "csv"

RSpec.describe HotelPortal::Reports::NonNationalCsvExportService do
  describe "#generate" do
    it "exports guest nationality rows" do
      report = double(
        "report",
        rows: [
          {
            guest_name: "Kenji Sato",
            guest_country: "Japan",
            date_of_birth: Date.new(1988, 5, 14),
            guest_home_address: "Tokyo",
            check_in: Date.new(2026, 7, 2),
            checked_in_at: Time.zone.parse("2026-07-02 14:00"),
            check_out: Date.new(2026, 7, 4)
          }
        ]
      )

      csv = described_class.new(report: report).generate
      rows = CSV.parse(csv.delete_prefix("\uFEFF"), headers: true)

      expect(rows.headers).to include("Full Name", "Nationality", "Date of Birth")
      expect(rows[0]["Full Name"]).to eq("Kenji Sato")
      expect(rows[0]["Nationality"]).to eq("Japan")
      expect(csv).to include("TOTAL")
    end
  end
end

# frozen_string_literal: true

require "rails_helper"
require "csv"

RSpec.describe HotelPortal::Reports::ExtraChargeCsvExportService do
  describe "#generate" do
    it "exports BOM-prefixed rows and totals using the hotel currency" do
      hotel = double("hotel", default_currency: "MYR")
      report = double(
        "report",
        rows: [
          {
            posting_date: Date.new(2026, 7, 2),
            booking_reference: "BK-001",
            folio_number: "FOL-001",
            guest_name: "Jane Doe",
            description: "Mini bar",
            category: "fb",
            amount: 25
          }
        ],
        totals: { transaction_count: 1, total_amount: 25 }
      )

      csv = described_class.new(hotel: hotel, report: report).generate
      rows = CSV.parse(csv.delete_prefix(described_class::BOM))

      expect(csv.bytes.first(3)).to eq([ 0xEF, 0xBB, 0xBF ])
      expect(rows.first).to eq([
        "Posting Date", "Booking Reference", "Folio Reference", "Guest Name",
        "Description", "Category", "Currency", "Amount"
      ])
      expect(rows.second).to eq([
        "2026-07-02", "BK-001", "FOL-001", "Jane Doe",
        "Mini bar", "F&B", "MYR", "25.00"
      ])
      expect(rows.last).to eq([ "TOTAL", nil, nil, nil, nil, "1 transaction", "MYR", "25.00" ])
    end

    it "exports headers and a zero total for an empty report" do
      hotel = double("hotel", default_currency: "MYR")
      report = double(
        "report",
        rows: [],
        totals: { transaction_count: 0, total_amount: 0 }
      )

      csv = described_class.new(hotel: hotel, report: report).generate
      rows = CSV.parse(csv.delete_prefix(described_class::BOM))

      expect(rows.first).to eq([
        "Posting Date", "Booking Reference", "Folio Reference", "Guest Name",
        "Description", "Category", "Currency", "Amount"
      ])
      expect(rows.last).to eq([ "TOTAL", nil, nil, nil, nil, "0 transactions", "MYR", "0.00" ])
    end

    it "generates valid UTF-8 for accented and non-Latin guest and description text" do
      hotel = double("hotel", default_currency: "MYR")
      report = double(
        "report",
        rows: [
          {
            posting_date: Date.new(2026, 7, 2),
            booking_reference: "BK-UNICODE",
            folio_number: "FOL-UNICODE",
            guest_name: "José 张伟",
            description: "Crème brûlée 東京",
            category: "fb",
            amount: 25
          }
        ],
        totals: { transaction_count: 1, total_amount: 25 }
      )

      csv = described_class.new(hotel: hotel, report: report).generate
      rows = CSV.parse(csv.delete_prefix(described_class::BOM))

      expect(csv.encoding).to eq(Encoding::UTF_8)
      expect(csv).to be_valid_encoding
      expect(rows.second.values_at(3, 4)).to eq([ "José 张伟", "Crème brûlée 東京" ])
    end

    it "neutralizes spreadsheet formulas in every user-controlled text column" do
      hotel = double("hotel", default_currency: "-currency")
      report = double(
        "report",
        rows: [
          {
            posting_date: Date.new(2026, 7, 2),
            booking_reference: "-booking",
            folio_number: "-folio",
            guest_name: "-guest",
            description: "-description",
            category: "-category",
            amount: 25
          }
        ],
        totals: { transaction_count: 1, total_amount: 25 }
      )

      csv = described_class.new(hotel: hotel, report: report).generate
      detail = CSV.parse(csv.delete_prefix(described_class::BOM)).second

      expect(detail).to eq([
        "2026-07-02", "'-booking", "'-folio", "'-guest",
        "'-description", "'-category", "'-currency", "25.00"
      ])
    end

    it "neutralizes every dangerous spreadsheet formula prefix" do
      dangerous_values = [ "=formula", "+formula", "-formula", "@formula", "\tformula", "\rformula" ]

      dangerous_values.each do |dangerous_value|
        hotel = double("hotel", default_currency: "MYR")
        report = double(
          "report",
          rows: [
            {
              posting_date: Date.new(2026, 7, 2),
              booking_reference: "BK-001",
              folio_number: "FOL-001",
              guest_name: "Jane Doe",
              description: dangerous_value,
              category: "fb",
              amount: 25
            }
          ],
          totals: { transaction_count: 1, total_amount: 25 }
        )

        csv = described_class.new(hotel: hotel, report: report).generate
        detail = CSV.parse(csv.delete_prefix(described_class::BOM)).second

        expect(detail[4]).to eq("'#{dangerous_value}")
        expect(detail[0]).to eq("2026-07-02")
        expect(detail[7]).to eq("25.00")
      end
    end
  end
end

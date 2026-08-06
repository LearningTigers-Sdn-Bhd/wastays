# frozen_string_literal: true

require "rails_helper"
require "pdf-reader"

RSpec.describe HotelPortal::Reports::ExtraChargePdfExportService do
  describe "#generate" do
    let(:hotel) { double("hotel", name: "Sample Hotel", default_currency: "MYR") }

    def report(rows:, totals:)
      double(
        "report",
        start_date: Date.new(2026, 7, 1),
        end_date: Date.new(2026, 7, 2),
        active_tab: "fb",
        rows: rows,
        totals: totals
      )
    end

    def extracted_text(pdf)
      reader = PDF::Reader.new(StringIO.new(pdf))
      reader.pages.map(&:text).join("\n")
    end

    it "renders a branded F&B charge report with its complete detail table" do
      report = report(
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

      pdf = described_class.new(hotel: hotel, report: report).generate
      text = extracted_text(pdf)

      expect(pdf).to start_with("%PDF")
      expect(pdf.bytesize).to be > 500
      expect(text).to include(
        "EXTRA CHARGE REPORT", "F&B", "Sample Hotel", "01 Jul 2026 - 02 Jul 2026",
        "Generated:", "Transactions", "1", "Total Amount", "MYR 25.00",
        "Posting Date", "Booking Ref", "Folio Ref", "Guest", "Description", "Category", "Currency", "Amount",
        "BK-001", "FOL-001", "Jane Doe", "Mini bar", "Total"
      )
      expect(text).to match(/Page 1 of \d+/)
    end

    it "renders an empty-state message and zero-value summary" do
      pdf = described_class.new(
        hotel: hotel,
        report: report(rows: [], totals: { transaction_count: 0, total_amount: 0 })
      ).generate
      text = extracted_text(pdf)

      expect(text).to include(
        "No extra charge transactions found for this period.",
        "Transactions", "0", "Total Amount", "MYR 0.00", "Total"
      )
    end

    it "renders accented and CJK hotel, guest, and description text" do
      unicode_hotel = double("hotel", name: "Hôtel 東京", default_currency: "MYR")
      unicode_report = report(
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

      text = extracted_text(described_class.new(hotel: unicode_hotel, report: unicode_report).generate)

      expect(text).to include("Hôtel 東京", "José 张伟", "Crème brûlée 東京")
    end

    it "preserves an oversized description across continuation rows and pages" do
      end_marker = "LONG-DESCRIPTION-END-MARKER"
      long_description = ("oversized description content " * 2_000) + end_marker
      long_report = report(
        rows: [
          {
            posting_date: Date.new(2026, 7, 2),
            booking_reference: "BK-LONG",
            folio_number: "FOL-LONG",
            guest_name: "Long Description Guest",
            description: long_description,
            category: "fb",
            amount: 25
          }
        ],
        totals: { transaction_count: 1, total_amount: 25 }
      )

      pdf = described_class.new(hotel: hotel, report: long_report).generate
      reader = PDF::Reader.new(StringIO.new(pdf))
      text = reader.pages.map(&:text).join("\n")

      expect(reader.page_count).to be > 1
      expect(text).to include(end_marker, "1 transaction", "MYR 25.00", "Total")
      expect(text.scan("Posting Date").size).to eq(reader.page_count)
    end
  end
end

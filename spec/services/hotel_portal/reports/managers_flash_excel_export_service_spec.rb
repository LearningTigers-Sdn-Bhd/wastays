# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::ManagersFlashExcelExportService do
  let(:report) do
    double(
      "ManagersFlashReportResult",
      rows: [
        {
          date: Date.new(2026, 5, 20),
          rooms_sold: 5,
          rooms_available: 10,
          occupancy_rate: 0.5,
          adr: 100.0,
          revpar: 50.0,
          room_revenue: 500.0,
          tax_amount: 50.0,
          total_revenue: 550.0
        }
      ],
      totals: {
        rooms_sold: 5,
        rooms_available: 10,
        occupancy_rate: 0.5,
        adr: 100.0,
        revpar: 50.0,
        room_revenue: 500.0,
        tax_amount: 50.0,
        total_revenue: 550.0
      }
    )
  end

  subject { described_class.new(report: report) }

  describe "#generate" do
    it "generates an Excel XML content" do
      xml_content = subject.generate
      expect(xml_content).to include('ss:Name="Summary"')
      expect(xml_content).to include('ss:Name="Manager Flash Report"')
      expect(xml_content).to include("500.00")
      expect(xml_content).to include("550.00")
    end
  end
end

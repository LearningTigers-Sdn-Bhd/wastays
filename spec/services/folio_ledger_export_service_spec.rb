# frozen_string_literal: true

require "rails_helper"

RSpec.describe FolioLedgerExportService do
  let(:hotel) { create(:hotel) }
  let(:start_date) { Date.current.beginning_of_month }
  let(:end_date) { Date.current.end_of_month }
  let(:service) { described_class.new(hotel: hotel, start_date: start_date, end_date: end_date) }

  describe "#generate_csv" do
    it "returns CSV string" do
      expect(service.generate_csv).to be_a(String)
      expect(service.generate_csv).to include("Posting Date")
    end
  end

  describe "#generate_xls" do
    it "returns XML string" do
      expect(service.generate_xls).to be_a(String)
      expect(service.generate_xls).to include("Workbook")
    end
  end

  describe "#totals" do
    it "returns a hash of totals" do
      expect(service.totals).to be_a(Hash)
      expect(service.totals).to have_key(:room_revenue)
    end
  end
end

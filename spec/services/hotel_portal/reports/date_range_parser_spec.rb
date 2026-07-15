# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::DateRangeParser do
  let(:hotel) { double("Hotel", business_date_for: Date.new(2026, 5, 10)) }

  describe ".parse_date" do
    it "parses valid date strings" do
      expect(described_class.parse_date("2026-05-15")).to eq(Date.new(2026, 5, 15))
    end

    it "returns nil for blank values" do
      expect(described_class.parse_date("")).to be_nil
      expect(described_class.parse_date(nil)).to be_nil
    end

    it "returns nil for invalid dates" do
      expect(described_class.parse_date("invalid-date")).to be_nil
    end
  end

  describe "#parse_range" do
    it "defaults to today when no params are given" do
      parser = described_class.new({}, hotel)
      expect(parser.parse_range).to eq([ Date.current, Date.current ])
      expect(parser.date_preset).to eq("today")
    end

    it "parses legacy date params" do
      parser = described_class.new({ date: "2026-05-01" }, hotel)
      expect(parser.parse_range).to eq([ Date.new(2026, 5, 1), Date.new(2026, 5, 1) ])
      expect(parser.date_preset).to eq("legacy_date")
    end

    it "parses preset ranges like last_month" do
      parser = described_class.new({ date_preset: "last_month" }, hotel)
      last_month = 1.month.ago.to_date
      expect(parser.parse_range).to eq([ last_month.beginning_of_month, last_month.end_of_month ])
    end

    it "parses specific months" do
      parser = described_class.new({ date_preset: "2026-03" }, hotel)
      expect(parser.parse_range).to eq([ Date.new(2026, 3, 1), Date.new(2026, 3, 31) ])
    end

    it "parses custom date range" do
      parser = described_class.new({ start_date: "2026-05-01", end_date: "2026-05-10" }, hotel)
      expect(parser.parse_range).to eq([ Date.new(2026, 5, 1), Date.new(2026, 5, 10) ])
    end
  end

  describe "#parse_as_of_date" do
    it "returns current date for today preset" do
      parser = described_class.new({ date_preset: "today" }, hotel)
      expect(parser.parse_as_of_date).to eq(Date.current)
    end

    it "returns end of last month for last_month preset" do
      parser = described_class.new({ date_preset: "last_month" }, hotel)
      expect(parser.parse_as_of_date).to eq(1.month.ago.to_date.end_of_month)
    end

    it "falls back to hotel business date or current date" do
      parser = described_class.new({}, hotel)
      expect(parser.parse_as_of_date).to eq(Date.new(2026, 5, 10))
    end
  end
end

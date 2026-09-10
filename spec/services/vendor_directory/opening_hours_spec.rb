# frozen_string_literal: true

require "rails_helper"

RSpec.describe VendorDirectory::OpeningHours do
  let(:zone) { ActiveSupport::TimeZone["Asia/Kuala_Lumpur"] }

  describe "#open_at?" do
    it "is open within a same-day window" do
      slot = described_class.new(days: "Mon – Sun", opens: "16:00", closes: "23:00")

      expect(slot.open_at?(zone.parse("2026-09-10 20:00"))).to be true # Thursday
      expect(slot.open_at?(zone.parse("2026-09-10 10:00"))).to be false
    end

    it "stays open past midnight when the window crosses it" do
      slot = described_class.new(days: "Mon – Sun", opens: "16:00", closes: "01:00")

      expect(slot.open_at?(zone.parse("2026-09-10 20:00"))).to be true  # Thursday evening
      expect(slot.open_at?(zone.parse("2026-09-11 00:30"))).to be true  # still Thursday's window, past midnight
      expect(slot.open_at?(zone.parse("2026-09-11 02:00"))).to be false # Friday's own window hasn't opened yet
    end

    it "only applies on the days it names" do
      slot = described_class.new(days: "Tue – Sat", opens: "11:00", closes: "22:00")

      expect(slot.open_at?(zone.parse("2026-09-15 12:00"))).to be true  # Tuesday
      expect(slot.open_at?(zone.parse("2026-09-14 12:00"))).to be false # Monday
    end

    it "is never open when marked closed" do
      slot = described_class.new(days: "Sun – Mon", opens: "Closed", closes: "")

      expect(slot.open_at?(zone.parse("2026-09-14 12:00"))).to be false
    end

    it "wraps a day range that ends earlier in the week than it starts" do
      slot = described_class.new(days: "Fri – Sun", opens: "10:00", closes: "18:00")

      expect(slot.open_at?(zone.parse("2026-09-12 12:00"))).to be true # Saturday
      expect(slot.open_at?(zone.parse("2026-09-15 12:00"))).to be false # Tuesday
    end
  end

  describe "#label" do
    it "renders the hours, or Closed" do
      expect(described_class.new(days: "Mon", opens: "09:00", closes: "17:00").label).to eq("09:00 – 17:00")
      expect(described_class.new(days: "Sun", opens: "Closed", closes: "").label).to eq("Closed")
    end
  end
end

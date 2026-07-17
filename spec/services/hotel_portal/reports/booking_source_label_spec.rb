# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::BookingSourceLabel do
  describe ".normalize" do
    it "maps known booking sources to their display labels" do
      expect(described_class.normalize("walk_in")).to eq("Walk-in")
      expect(described_class.normalize("agoda")).to eq("Agoda")
      expect(described_class.normalize("whatsapp")).to eq("WhatsApp")
      expect(described_class.normalize("corporate")).to eq("Corporate")
      expect(described_class.normalize("internal")).to eq("Direct")
    end

    it "titleizes unrecognized sources" do
      expect(described_class.normalize("booking_dot_com")).to eq("Booking Dot Com")
    end

    it "treats blank or nil sources as unknown" do
      expect(described_class.normalize(nil)).to eq("Unknown")
      expect(described_class.normalize("")).to eq("Unknown")
      expect(described_class.normalize("   ")).to eq("Unknown")
    end

    it "accepts non-string sources by coercing to string" do
      expect(described_class.normalize(:agoda)).to eq("Agoda")
    end
  end
end

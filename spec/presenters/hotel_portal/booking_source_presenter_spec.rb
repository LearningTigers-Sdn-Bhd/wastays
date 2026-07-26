# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::BookingSourcePresenter do
  describe "#label" do
    it "resolves known manual sources" do
      expect(described_class.new("walk_in").label).to eq("Walk-in")
      expect(described_class.new("whatsapp").label).to eq("WhatsApp")
    end

    it "normalizes casing and punctuation for OTA sources" do
      expect(described_class.new("booking.com").label).to eq("Booking.com")
      expect(described_class.new("Booking.com").label).to eq("Booking.com")
      expect(described_class.new("BOOKING_COM").label).to eq("Booking.com")
      expect(described_class.new("  agoda ").label).to eq("Agoda")
    end

    it "humanizes unrecognized sources" do
      expect(described_class.new("unknown_ota_xyz").label).to eq("Unknown Ota Xyz")
    end

    it "returns Unknown for blank sources" do
      expect(described_class.new(nil).label).to eq("Unknown")
      expect(described_class.new("").label).to eq("Unknown")
    end
  end

  describe "#ota?" do
    it "is true only for the recognized OTA list regardless of casing" do
      %w[booking_com agoda expedia traveloka airbnb].each do |source|
        expect(described_class.new(source)).to be_ota
      end
      expect(described_class.new("Booking.com")).to be_ota
    end

    it "is false for channel-manager passthrough values and unrecognized sources" do
      expect(described_class.new("channex")).not_to be_ota
      expect(described_class.new("channel_manager")).not_to be_ota
      expect(described_class.new("unknown_ota_xyz")).not_to be_ota
      expect(described_class.new("walk_in")).not_to be_ota
    end
  end

  describe "badge attributes" do
    it "are present only for OTA sources" do
      presenter = described_class.new("booking_com")
      expect(presenter.badge_color).to eq("#003580")
      expect(presenter.badge_initial).to eq("B")
      expect(presenter.badge_text_color).to eq("#FFFFFF")

      non_ota = described_class.new("walk_in")
      expect(non_ota.badge_color).to be_nil
      expect(non_ota.badge_initial).to be_nil
    end
  end

  describe "#icon" do
    it "returns a generic fallback icon for unrecognized sources" do
      expect(described_class.new("unknown_ota_xyz").icon).to eq("link")
    end

    it "returns a globe icon for OTA and channel-manager sources" do
      expect(described_class.new("agoda").icon).to eq("globe")
      expect(described_class.new("channex").icon).to eq("globe")
    end
  end

  describe "#logo" do
    it "is nil when the matching booking source has no attached logo" do
      expect(described_class.new("booking_com").logo).to be_nil
    end

    it "returns the attached logo when present" do
      source = create(:booking_source, key: "logo_test_ota")
      source.logo.attach(io: Rails.root.join("spec/fixtures/files/sample_image.jpg").open, filename: "logo.jpg", content_type: "image/jpeg")

      expect(described_class.new("logo_test_ota").logo).to be_attached
    end
  end

  describe "an inactive source" do
    it "still resolves for display even though it's excluded from dropdowns" do
      create(:booking_source, key: "retired_channel", label: "Retired Channel", kind: "ota", active: false)

      expect(described_class.new("retired_channel").label).to eq("Retired Channel")
      expect(described_class.ota_options.map(&:last)).not_to include("retired_channel")
    end
  end

  describe "dropdown option groups" do
    it "returns manual, OTA, and other-channel option pairs sourced from the database" do
      expect(described_class.manual_options).to include([ "Walk-in", "walk_in" ], [ "WhatsApp", "whatsapp" ])
      expect(described_class.ota_options).to include([ "Booking.com", "booking_com" ], [ "Agoda", "agoda" ])
      expect(described_class.other_channel_options).to include([ "Channel Manager", "channel_manager" ])
    end
  end
end

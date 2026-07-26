# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookingSource do
  describe "normalization" do
    it "normalizes the key to lowercase underscore form" do
      source = create(:booking_source, key: "Booking.com Custom")
      expect(source.key).to eq("booking_com_custom")
    end

    it "upcases hex colors" do
      source = create(:booking_source, badge_color: "#abcdef", badge_text_color: "#123456")
      expect(source).to have_attributes(badge_color: "#ABCDEF", badge_text_color: "#123456".upcase)
    end
  end

  describe "validations" do
    it "requires a unique key" do
      create(:booking_source, key: "duplicate_source")
      duplicate = build(:booking_source, key: "duplicate_source")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:key]).to be_present
    end

    it "requires a label and a valid kind" do
      source = build(:booking_source, label: nil, kind: "not_a_kind")

      expect(source).not_to be_valid
      expect(source.errors[:label]).to be_present
      expect(source.errors[:kind]).to be_present
    end

    it "rejects malformed hex colors" do
      source = build(:booking_source, badge_color: "blue")

      expect(source).not_to be_valid
      expect(source.errors[:badge_color]).to be_present
    end

    it "rejects an icon name that isn't a real Lucide icon" do
      source = build(:booking_source, icon: "not-a-real-lucide-icon")

      expect(source).not_to be_valid
      expect(source.errors[:icon]).to be_present
    end

    it "accepts a known Lucide icon name" do
      source = build(:booking_source, icon: "credit-card")

      expect(source).to be_valid
    end

    it "rejects a non-image logo attachment" do
      source = build(:booking_source)
      source.logo.attach(
        io: StringIO.new("not an image"),
        filename: "notes.txt",
        content_type: "text/plain"
      )

      expect(source).not_to be_valid
      expect(source.errors[:logo]).to be_present
    end
  end

  describe ".find_by_source" do
    it "matches regardless of casing and punctuation" do
      source = create(:booking_source, key: "custom_ota", label: "Custom OTA")

      expect(described_class.find_by_source("Custom OTA")).to eq(source)
      expect(described_class.find_by_source("CUSTOM_OTA")).to eq(source)
    end

    it "returns nil for an unrecognized source" do
      expect(described_class.find_by_source("totally_unknown")).to be_nil
    end
  end

  describe ".options_for" do
    it "excludes inactive sources" do
      create(:booking_source, key: "inactive_ota", kind: "ota", active: false)

      expect(described_class.ota_options.map(&:last)).not_to include("inactive_ota")
    end
  end

  describe ".seed_defaults!" do
    it "is idempotent and does not duplicate rows on repeat calls" do
      expect { described_class.seed_defaults! }.to change(described_class, :count).by(0)
    end

    it "seeds the expected default OTA keys" do
      expect(described_class.where(kind: "ota").pluck(:key)).to include("booking_com", "agoda", "expedia", "traveloka", "airbnb")
    end
  end
end

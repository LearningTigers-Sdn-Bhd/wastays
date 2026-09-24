# frozen_string_literal: true

require "rails_helper"

RSpec.describe VendorDirectory::Offer do
  def build_offer(valid_until: nil, remaining: nil)
    described_class.new(
      id: "one-free-coffee", vendor_id: "kk-roasters", title: "One free coffee",
      subtitle: nil, kind: "free_item", value_label: "Free", terms: [],
      valid_until: valid_until, per_guest_limit: 1, remaining: remaining
    )
  end

  describe "#expires_on" do
    it "parses the fixture's date string, and stays nil when the offer has no end" do
      expect(build_offer(valid_until: "2026-12-31").expires_on).to eq(Date.new(2026, 12, 31))
      expect(build_offer.expires_on).to be_nil
    end
  end

  describe "#expiring_soon?" do
    it "is true within thirty days of the end date" do
      travel_to Time.zone.parse("2026-09-14 10:00") do
        expect(build_offer(valid_until: "2026-09-30").expiring_soon?).to be(true)
        expect(build_offer(valid_until: "2026-10-14").expiring_soon?).to be(true)
        expect(build_offer(valid_until: "2026-10-15").expiring_soon?).to be(false)
      end
    end

    # An offer with no end date never runs out, so it must never be badged as
    # about to.
    it "is false when the offer has no end date" do
      expect(build_offer.expiring_soon?).to be(false)
    end
  end

  describe "#scarce?" do
    it "is true at or under twenty-five remaining, and false when the count is unknown" do
      expect(build_offer(remaining: 25).scarce?).to be(true)
      expect(build_offer(remaining: 26).scarce?).to be(false)
      expect(build_offer(remaining: nil).scarce?).to be(false)
    end
  end

  describe "#to_param" do
    it "is the offer id, so a claim URL names the deal" do
      expect(build_offer.to_param).to eq("one-free-coffee")
    end
  end
end

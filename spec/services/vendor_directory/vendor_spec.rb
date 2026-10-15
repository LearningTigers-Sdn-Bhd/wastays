# frozen_string_literal: true

require "rails_helper"

RSpec.describe VendorDirectory::Vendor do
  let(:zone) { ActiveSupport::TimeZone["Asia/Kuala_Lumpur"] }

  def build_vendor(hours, reviews: [])
    described_class.new(
      id: "test", category_slug: "food-drink", name: "Test Vendor", tagline: "",
      accent: "amber", price_range: "$", tags: [], summary: "", address: "",
      phone: nil, distance_km: nil, walking_minutes: nil, hours: hours,
      google_maps_url: "", latitude: nil, longitude: nil, offers: [],
      photo_url: "", dietary_tags: [], reviews: reviews
    )
  end

  describe "#open_now?" do
    it "is true when any hours slot covers the given time" do
      vendor = build_vendor([
        VendorDirectory::OpeningHours.new(days: "Mon – Sun", opens: "16:00", closes: "23:00")
      ])

      expect(vendor.open_now?(time: zone.parse("2026-09-10 20:00"))).to be true
      expect(vendor.open_now?(time: zone.parse("2026-09-10 10:00"))).to be false
    end
  end

  describe "#next_open_at" do
    it "picks the soonest opening across every slot" do
      vendor = build_vendor([
        VendorDirectory::OpeningHours.new(days: "Tue – Sat", opens: "11:00", closes: "22:00"),
        VendorDirectory::OpeningHours.new(days: "Sun – Mon", opens: "Closed", closes: "")
      ])

      # Monday morning: Tue-Sat's slot opens the next day; the closed slot
      # contributes nothing.
      expect(vendor.next_open_at(time: zone.parse("2026-09-14 09:00")))
        .to eq(zone.parse("2026-09-15 11:00"))
    end

    it "is nil when every slot is permanently closed" do
      vendor = build_vendor([ VendorDirectory::OpeningHours.new(days: "Sun", opens: "Closed", closes: "") ])

      expect(vendor.next_open_at(time: zone.parse("2026-09-14 09:00"))).to be_nil
    end

    it "is nil when there are no hours at all" do
      vendor = build_vendor([])

      expect(vendor.next_open_at(time: zone.parse("2026-09-14 09:00"))).to be_nil
    end
  end

  describe "#closing_soon?" do
    let(:vendor) do
      build_vendor([ VendorDirectory::OpeningHours.new(days: "Mon – Sun", opens: "16:00", closes: "23:00") ])
    end

    it "is true within the default 45-minute window before closing" do
      expect(vendor.closing_soon?(time: zone.parse("2026-09-10 22:20"))).to be true
    end

    it "is false earlier in the same open window" do
      expect(vendor.closing_soon?(time: zone.parse("2026-09-10 18:00"))).to be false
    end

    it "is false while closed -- there is nothing counting down" do
      expect(vendor.closing_soon?(time: zone.parse("2026-09-10 10:00"))).to be false
    end

    it "respects a custom window" do
      expect(vendor.closing_soon?(time: zone.parse("2026-09-10 21:30"), within: 2.hours)).to be true
    end
  end

  describe "#average_rating" do
    it "is nil with no reviews" do
      expect(build_vendor([]).average_rating).to be_nil
    end

    it "averages and rounds to one decimal place" do
      vendor = build_vendor([], reviews: [
        VendorDirectory::Review.new(guest_name: "A", rating: 5, comment: "", posted_at: Date.current),
        VendorDirectory::Review.new(guest_name: "B", rating: 4, comment: "", posted_at: Date.current),
        VendorDirectory::Review.new(guest_name: "C", rating: 4, comment: "", posted_at: Date.current)
      ])

      expect(vendor.average_rating).to eq(4.3)
      expect(vendor.review_count).to eq(3)
    end
  end
end

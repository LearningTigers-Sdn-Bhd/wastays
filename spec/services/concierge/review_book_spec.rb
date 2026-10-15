# frozen_string_literal: true

require "rails_helper"

RSpec.describe Concierge::ReviewBook do
  subject(:book) { described_class.new(session: session) }

  let(:session) { {} }

  def build_vendor(reviews: [])
    VendorDirectory::Vendor.new(
      id: "kk-roasters", category_slug: "food-drink", name: "KK Roasters", tagline: "",
      accent: "amber", price_range: "$", tags: [], summary: "", address: "",
      phone: nil, distance_km: nil, walking_minutes: nil, hours: [],
      google_maps_url: "", latitude: nil, longitude: nil, offers: [],
      photo_url: "", dietary_tags: [], reviews: reviews
    )
  end

  def seeded_review(name, posted_at)
    VendorDirectory::Review.new(guest_name: name, rating: 4, comment: "Fine", posted_at: posted_at)
  end

  describe "#add!" do
    it "keeps a guest's review in the session so it survives the redirect back" do
      book.add!(vendor_id: "kk-roasters", guest_name: "Aisha", rating: 5, comment: "Great coffee")

      expect(session[described_class::SESSION_KEY]["kk-roasters"].size).to eq(1)
      expect(described_class.new(session: session).mine_for("kk-roasters").map(&:guest_name)).to eq([ "Aisha" ])
    end

    it "stores a blank comment as nothing rather than an empty string" do
      review = book.add!(vendor_id: "kk-roasters", guest_name: "Aisha", rating: 5, comment: "")

      expect(review.comment).to be_nil
    end

    it "keeps reviews for different vendors apart" do
      book.add!(vendor_id: "kk-roasters", guest_name: "Aisha", rating: 5, comment: nil)
      book.add!(vendor_id: "sabah-grill", guest_name: "Ben", rating: 3, comment: nil)

      expect(book.mine_for("kk-roasters").map(&:guest_name)).to eq([ "Aisha" ])
      expect(book.mine_for("sabah-grill").map(&:guest_name)).to eq([ "Ben" ])
    end
  end

  describe "#for" do
    it "merges the vendor's seeded reviews with this guest's own, newest first" do
      vendor = build_vendor(reviews: [
        seeded_review("Old", Time.zone.parse("2026-01-01 09:00")),
        seeded_review("Newer", Time.zone.parse("2026-06-01 09:00"))
      ])

      travel_to Time.zone.parse("2026-09-14 10:00") do
        book.add!(vendor_id: vendor.id, guest_name: "Mine", rating: 5, comment: nil)

        expect(book.for(vendor).map(&:guest_name)).to eq(%w[Mine Newer Old])
      end
    end

    it "returns the seeded reviews untouched when this guest has left none" do
      vendor = build_vendor(reviews: [ seeded_review("Only", Time.zone.parse("2026-01-01 09:00")) ])

      expect(book.for(vendor).map(&:guest_name)).to eq([ "Only" ])
    end
  end

  describe "#mine_for" do
    it "is empty for a vendor this guest has not reviewed" do
      expect(book.mine_for("unknown-vendor")).to eq([])
    end
  end
end

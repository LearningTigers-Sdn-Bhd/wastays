# frozen_string_literal: true

require "rails_helper"

RSpec.describe VendorDirectory do
  describe ".featured_in" do
    it "caps the rail at three offers, one per vendor" do
      featured = described_class.featured_in("food-drink")

      expect(featured.size).to eq(3)
      expect(featured.map(&:vendor_id).uniq.size).to eq(3)
    end

    it "never exceeds the number of vendors that have an offer" do
      # shopping has one vendor with offers (handicraft-market) and one with
      # none (imago-mall) -- deduping by vendor means the rail cannot show more
      # than one card even though that vendor has several offers.
      featured = described_class.featured_in("shopping")

      expect(featured.size).to eq(1)
    end
  end

  describe ".offers_in" do
    it "returns every offer in the category, not deduped by vendor" do
      offers = described_class.offers_in("food-drink")

      expect(offers.size).to be > described_class.featured_in("food-drink").size
      expect(offers.map(&:vendor_id).uniq.size).to be > 1
    end
  end
end

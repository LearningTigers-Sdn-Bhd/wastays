# frozen_string_literal: true

require "rails_helper"

RSpec.describe VendorDirectory::MockAdapter do
  subject(:adapter) { described_class.new }

  # This reads the checked-in fixture rather than a stub: the point of the
  # adapter is that config/vendor_directory/mock.yml keeps producing the value
  # objects the UI renders, so a bad edit to that file should fail here rather
  # than on a page.
  describe "#categories" do
    it "builds a category per fixture entry" do
      categories = adapter.categories

      expect(categories).to all(be_a(VendorDirectory::Category))
      expect(categories.map(&:slug)).to all(be_present)
      expect(categories.map(&:name)).to all(be_present)
    end
  end

  describe "#vendors" do
    it "builds vendors whose offers know the vendor they belong to" do
      vendor = adapter.vendors.find { |candidate| candidate.offers.any? }

      expect(vendor).to be_a(VendorDirectory::Vendor)
      expect(vendor.offers).to all(be_a(VendorDirectory::Offer))
      expect(vendor.offers.map(&:vendor_id).uniq).to eq([ vendor.id ])
    end

    it "points every vendor at a category the fixture defines" do
      slugs = adapter.categories.map(&:slug)

      expect(adapter.vendors.map(&:category_slug).uniq).to all(be_in(slugs))
    end

    it "gives a vendor without its own photograph a stable placeholder" do
      vendor = adapter.vendors.first

      expect(vendor.photo_url).to be_present
      expect(adapter.vendors.first.photo_url).to eq(vendor.photo_url)
    end

    it "builds the seeded reviews as the same shape a guest's own review takes" do
      vendor = adapter.vendors.find { |candidate| candidate.reviews.any? }

      expect(vendor.reviews).to all(be_a(VendorDirectory::Review))
      expect(vendor.reviews.map(&:rating_i)).to all(be_between(1, 5))
    end

    it "reads opening hours into slots rather than leaving them as hashes" do
      vendor = adapter.vendors.find { |candidate| candidate.hours.any? }

      expect(vendor.hours).to all(be_a(VendorDirectory::OpeningHours))
    end
  end
end

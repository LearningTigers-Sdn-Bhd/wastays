require "rails_helper"

RSpec.describe HotelsQuery do
  describe "#call" do
    it "filters setup statuses as one admin-facing group" do
      registered = create(:hotel, status: "registered")
      inventory_incomplete = create(:hotel, status: "inventory_incomplete")
      create(:hotel, status: "approved")

      expect(described_class.new.call(status: "setup")).to contain_exactly(registered, inventory_incomplete)
    end

    it "filters approved and live hotels as one active group" do
      approved = create(:hotel, status: "approved")
      live = create(:hotel, status: "live")
      create(:hotel, status: "suspended")

      expect(described_class.new.call(status: "active")).to contain_exactly(approved, live)
    end
  end
end

require "rails_helper"

RSpec.describe HotelPortal::BookingsHelper, type: :helper do
  describe "#auto_charge_options" do
    let(:hotel) { create(:hotel) }

    it "lists only active auto-apply charges with their rate and unit" do
      jetty = create(:hotel_extra_charge, hotel: hotel, pricing_type: "fixed", rate_value: 10,
        charging_unit: "per_person", allow_amount_override: false, auto_apply: true)
      create(:hotel_extra_charge, hotel: hotel, pricing_type: "fixed", rate_value: 5, charging_unit: "per_item")

      expect(helper.auto_charge_options(hotel)).to eq([ { name: jetty.name, rate: "10.0", unit: "per_person", children: true } ])
    end
  end
end

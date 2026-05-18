require "rails_helper"

RSpec.describe HotelOps::SyncPricingRules do
  let(:hotel) { create(:hotel) }

  describe "#call" do
    it "stores general, weekends, school holiday, walk-in, and public holiday rules" do
      result = described_class.new(
        hotel: hotel,
        gp_price: "120",
        gp_start_date: "2026-05-01",
        gp_end_date: "2026-05-31",
        wk_price: "180",
        wk_start_date: "2026-05-01",
        wk_end_date: "2026-05-31",
        weekend_days: [ "5", "6", "0" ],
        sc_price: "220",
        sc_start_date: "2026-05-20",
        sc_end_date: "2026-05-31",
        wi_price: "250",
        wi_start_date: "2026-05-01",
        wi_end_date: "2026-05-31",
        public_holidays: [
          { name: "Kaamatan", start_date: "2026-05-30", end_date: "2026-05-31", price: "320" }
        ]
      ).call

      expect(result[:success]).to eq(true)
      expect(hotel.pricing_rules.pluck(:rule_type)).to include("general", "weekends", "school_holiday", "walk_in", "public_holiday")
    end

    it "replaces old rules when applying new inputs" do
      hotel.pricing_rules.create!(rule_type: "general", name: "General", price: 99)

      described_class.new(
        hotel: hotel,
        gp_price: "140",
        gp_start_date: "2026-06-01",
        gp_end_date: "",
        wk_price: nil,
        wk_start_date: nil,
        wk_end_date: nil,
        weekend_days: [],
        sc_price: nil,
        sc_start_date: nil,
        sc_end_date: nil,
        wi_price: nil,
        wi_start_date: nil,
        wi_end_date: nil,
        public_holidays: []
      ).call

      expect(hotel.pricing_rules.count).to eq(1)
      expect(hotel.pricing_rules.first.price.to_f).to eq(140.0)
    end
  end
end

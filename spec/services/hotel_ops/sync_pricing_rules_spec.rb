require "rails_helper"

RSpec.describe HotelOps::SyncPricingRules do
  let(:hotel) { create(:hotel) }
  let(:base_params) do
    {
      hotel: hotel,
      gp_price: 100,
      gp_start_date: "2026-05-20",
      gp_end_date: "2026-05-30",
      wk_price: 150,
      wk_start_date: "2026-05-20",
      wk_end_date: "2026-05-30",
      weekend_days: [ 5, 6 ],
      school_holidays: [],
      public_holidays: []
    }
  end

  describe "#call" do
    it "returns the union of old and new date ranges when rules are moved" do
      # Initial sync: May 20 - May 30
      described_class.new(**base_params).call

      # Move dates: May 25 - June 5
      move_params = base_params.merge(
        gp_start_date: "2026-05-25",
        gp_end_date: "2026-06-05",
        wk_start_date: "2026-05-25",
        wk_end_date: "2026-06-05"
      )

      result = described_class.new(**move_params).call

      expect(result[:success]).to eq(true)
      # Should cover original start (May 20) to new end (June 5)
      expect(result[:apply_start_date].to_s).to eq("2026-05-20")
      expect(result[:apply_end_date].to_s).to eq("2026-06-05")
    end

    it "covers old holiday dates when they are deleted" do
      # Initial sync with a holiday
      holiday_params = base_params.merge(
        public_holidays: [ { name: "Labor Day", price: 200, start_date: "2026-05-01", end_date: "2026-05-01" } ]
      )
      described_class.new(**holiday_params).call

      # Sync again without the holiday
      result = described_class.new(**base_params).call

      expect(result[:success]).to eq(true)
      # Should cover the deleted holiday date (May 1) through the existing rules (May 30)
      expect(result[:apply_start_date].to_s).to eq("2026-05-01")
      expect(result[:apply_end_date].to_s).to eq("2026-05-30")
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::NightlyChargeCalculation, type: :service do
  let(:dummy_class) do
    Class.new do
      include Folios::NightlyChargeCalculation
      def public_nightly_amount(total, booking, date)
        nightly_amount(total, booking, date)
      end
    end
  end
  let(:instance) { dummy_class.new }
  let(:booking) { build(:booking, check_in: Date.new(2026, 5, 18), check_out: Date.new(2026, 5, 21)) } # 3 nights

  describe "#nightly_amount" do
    it "calculates per-night amount" do
      # 300 / 3 = 100
      expect(instance.public_nightly_amount(300.0, booking, Date.new(2026, 5, 18))).to eq(100.0)
      expect(instance.public_nightly_amount(300.0, booking, Date.new(2026, 5, 19))).to eq(100.0)
    end

    it "adjusts for rounding errors on the last night" do
      # 100 / 3 = 33.3333... -> 33.33 for first 2 nights, 33.34 for last night
      expect(instance.public_nightly_amount(100.0, booking, Date.new(2026, 5, 18))).to eq(33.33)
      expect(instance.public_nightly_amount(100.0, booking, Date.new(2026, 5, 19))).to eq(33.33)
      expect(instance.public_nightly_amount(100.0, booking, Date.new(2026, 5, 20))).to eq(33.34)
    end
  end
end

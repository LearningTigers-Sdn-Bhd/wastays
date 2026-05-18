# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::NightlyChargeCalculation do
  subject(:calculator) do
    Class.new do
      include Folios::NightlyChargeCalculation

      public :nightly_amount, :tax_lines_for, :tax_line_amount, :tax_line_name, :tax_line_identity
    end.new
  end

  describe "#nightly_amount" do
    let(:booking) { build(:booking, check_in: Date.current, check_out: Date.current + 3.days) }

    it "splits totals across nights and keeps rounding remainder on the final night" do
      expect(calculator.nightly_amount(100, booking, booking.check_in)).to eq(33.33.to_d)
      expect(calculator.nightly_amount(100, booking, booking.check_out - 1.day)).to eq(33.34.to_d)
    end
  end

  describe "#tax_lines_for" do
    it "falls back to tourism tax when tax lines are blank" do
      booking = build(:booking, tax_lines: [], tourism_tax_amount: 10)

      expect(calculator.tax_lines_for(booking)).to eq(
        [ { "name" => "Tourism Tax", "amount" => 10, "type" => "tourism_tax" } ]
      )
    end
  end
end

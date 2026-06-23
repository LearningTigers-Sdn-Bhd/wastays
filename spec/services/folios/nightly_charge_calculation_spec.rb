# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::NightlyChargeCalculation do
  subject(:calculator) do
    Class.new do
      include Folios::NightlyChargeCalculation

      public :nightly_amount, :nightly_room_amount, :tax_lines_for, :tax_postings_for, :tax_line_amount, :tax_line_name, :tax_line_identity
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

  describe "#nightly_room_amount" do
    it "uses the contracted nightly rate snapshot when present" do
      booking = create(:booking, check_in: Date.current, check_out: Date.current + 2.days)
      booking_room = create(:booking_room,
        booking: booking,
        subtotal: 1_000,
        nightly_rate_snapshot: {
          Date.current.iso8601 => { "price" => "125.50" }
        })

      expect(calculator.nightly_room_amount(booking_room, Date.current)).to eq(125.50.to_d)
    end
  end
end

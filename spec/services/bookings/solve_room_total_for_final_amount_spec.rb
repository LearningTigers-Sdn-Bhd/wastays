# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::SolveRoomTotalForFinalAmount do
  let(:hotel) { create(:hotel, sst_enabled: true) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:rate_plan) { room_type.standard_rate_plan }
  let(:check_in) { Date.current + 1.day }
  let(:check_out) { Date.current + 3.days }
  let(:guest_country) { "Malaysia" }

  before do
    (check_in...check_out).each { |date| create(:room_rate, room_type: room_type, date: date, price: 100.0) }
  end

  def call(target_total)
    described_class.new(
      hotel: hotel, room_type: room_type, rate_plan: rate_plan,
      check_in: check_in, check_out: check_out, guest_country: guest_country,
      target_total: target_total
    ).call
  end

  def actual_total_for(snapshot)
    snapshot.room_total + Booking.non_tourism_tax_total_for(snapshot.tax_lines)
  end

  context "with a single percentage tax" do
    before do
      room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
      room_code.update!(is_taxable: true)
      room_code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
    end

    it "backs the exact room net out of a chosen final total" do
      snapshot = call("500.00")

      expect(actual_total_for(snapshot)).to eq(500.00)
      expect(snapshot.room_total).to be < 500.00
      expect(snapshot.tax_lines.sum { |line| line["amount"].to_d }).to be > 0
    end
  end

  context "with a percentage tax and a flat fee stacked on the same basis" do
    let!(:heritage_fee) { create(:hotel_tax, hotel: hotel, name: "Heritage Fee", rate_type: "flat", amount: 2.0) }

    before do
      room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
      room_code.update!(is_taxable: true)
      room_code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
      room_code.transaction_code_taxes.create!(hotel_tax: heritage_fee)
    end

    it "still converges to the chosen final total" do
      snapshot = call("437.50")

      expect(actual_total_for(snapshot)).to eq(437.50)
    end

    it "matches a total that already equals the untaxed quote plus its own taxes" do
      quoted = Bookings::BuildFinancialSnapshot.new(
        hotel: hotel, room_type: room_type, rate_plan: rate_plan, check_in: check_in, check_out: check_out, guest_country: guest_country
      ).call
      quoted_total = quoted.room_total + Booking.non_tourism_tax_total_for(quoted.tax_lines)

      snapshot = call(quoted_total.to_s)

      expect(snapshot.room_total).to eq(quoted.room_total)
      expect(actual_total_for(snapshot)).to eq(quoted_total)
    end
  end

  context "with no room-revenue taxes configured" do
    it "the room net equals the final total exactly" do
      snapshot = call("300.00")

      expect(snapshot.room_total).to eq(300.00)
      expect(actual_total_for(snapshot)).to eq(300.00)
    end
  end

  context "with a total too small to clear a flat fee" do
    let!(:heritage_fee) { create(:hotel_tax, hotel: hotel, name: "Heritage Fee", rate_type: "flat", amount: 50.0) }

    before do
      room_code = hotel.transaction_codes.find_by!(system_key: "room_revenue")
      room_code.update!(is_taxable: true)
      room_code.transaction_code_taxes.create!(hotel_tax: heritage_fee)
    end

    it "floors the room net at a cent rather than going negative" do
      snapshot = call("10.00")

      expect(snapshot.room_total).to be >= 0
    end
  end
end

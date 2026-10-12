# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::BuildRoomChargeCorrectionSnapshot, frozen_time: :business_day do
  include_context "completed room-charge correction"

  def build(amount = "86.40")
    described_class.new(booking: booking, nightly_amounts: amounts_for(amount)).call
  end

  it "solves a tax-inclusive amount with the original percentage tax" do
    hotel.update!(sst_enabled: false)
    snapshot = build
    expect(snapshot.room_attributes[:subtotal]).to eq(80)
    expect(snapshot.booking_attributes[:total_amount]).to eq("86.4".to_d)
    expect(snapshot.booking_attributes[:tax_posting_snapshot].fetch(correction_date.iso8601).sole).to include("rate" => "8.0", "amount" => "6.4")
    expect(booking.reload.total_amount).to eq(108)
  end

  %w[-1 abc NaN Infinity 1.001].each do |amount|
    it "rejects invalid input #{amount}" do
      expect { build(amount) }.to raise_error(ArgumentError, /nonnegative/)
    end
  end

  it "accepts zero room and percentage-tax amounts" do
    snapshot = build("0")
    expect(snapshot.room_attributes[:subtotal]).to eq(0)
    expect(snapshot.booking_attributes[:total_amount]).to eq(0)
    expect(snapshot.booking_attributes[:tax_posting_snapshot].fetch(correction_date.iso8601).sole["amount"].to_d).to eq(0)
  end

  it "preserves Tourism Tax and unrelated taxes" do
    key = correction_date.iso8601
    tourism = { "name" => "Tourism Tax", "type" => "tourism_tax", "basis" => "room_night", "amount" => "10", "rate" => "10", "source" => "historical" }
    other = { "name" => "Other charge tax", "type" => "custom", "basis" => "nightly_room_charge", "amount" => "2", "rate" => "2", "rate_type" => "flat", "source" => "historical", "source_transaction_code_id" => -1 }
    booking.update!(tax_posting_snapshot: { key => booking.tax_posting_snapshot.fetch(key) + [ tourism, other ] },
      tax_lines: booking.tax_lines + [ tourism.slice("name", "type", "source", "amount"), other.slice("name", "type", "source", "amount") ],
      tourism_tax_amount: 10, tourism_tax_applied: true, total_amount: 110)
    snapshot = build
    expect(snapshot.booking_attributes[:tax_posting_snapshot].fetch(key).last(2)).to eq([ tourism, other ])
    expect(snapshot.booking_attributes[:tax_lines].last(2)).to eq(booking.tax_lines.last(2))
    expect(snapshot.booking_attributes[:total_amount]).to eq("88.4".to_d)
    expect(snapshot.charge_keys.length).to eq(2)
  end

  it "rejects missing and inconsistent historical rules" do
    booking.update!(tax_posting_snapshot: {})
    expect { build }.to raise_error(ArgumentError, /missing/)
  end

  it "rejects incomplete recorded tax calculation metadata" do
    taxes = booking.tax_posting_snapshot.deep_dup
    taxes.fetch(correction_date.iso8601).sole.delete("rate")
    booking.update!(tax_posting_snapshot: taxes)
    expect { build }.to raise_error(ArgumentError, /incomplete/)
  end

  it "rejects an amount that cannot cover a recorded flat tax" do
    taxes = booking.tax_posting_snapshot.deep_dup
    taxes.fetch(correction_date.iso8601).sole.merge!("rate_type" => "flat", "rate" => "8")
    booking.update!(tax_posting_snapshot: taxes)
    expect { build("4") }.to raise_error(ArgumentError, /cannot match/)
  end

  context "multiple nights with different recorded rates" do
    let(:night_count) { 2 }

    it "changes only the nights whose amount differs" do
      second_date = (correction_date + 1).iso8601
      snapshot = described_class.new(booking: booking, nightly_amounts: { correction_date.iso8601 => "108", second_date => "86.40" }).call
      expect(snapshot.nights.map { |night| night[:date] }).to eq([ second_date ])
      expect(snapshot.room_attributes[:nightly_rate_snapshot].fetch(correction_date.iso8601)).to eq(room.nightly_rate_snapshot.fetch(correction_date.iso8601))
      expect(snapshot.charge_keys.length).to eq(2)
    end

    it "lists the recorded tax-inclusive amount for each night" do
      current = described_class.new(booking: booking, nightly_amounts: {}).current_nights
      expect(current).to eq([ { date: correction_date.iso8601, current_amount: 108 }, { date: (correction_date + 1).iso8601, current_amount: 108 } ])
    end

    it "rejects amounts for dates outside the stay" do
      expect { described_class.new(booking: booking, nightly_amounts: { "2000-01-01" => "50" }).call }.to raise_error(ArgumentError, /nights of this stay/)
    end

    it "applies one amount to each date without averaging original prices" do
      rates = room.nightly_rate_snapshot.deep_dup
      rates.fetch(correction_date.iso8601)["price"] = "120"
      room.update!(nightly_rate_snapshot: rates, subtotal: 220)
      booking.booking_rooms.reload
      snapshot = build
      expect(snapshot.nights.map { |night| night[:current_amount] }).to eq([ "128.0", "108.0" ])
      expect(snapshot.nights.map { |night| night[:corrected_amount] }).to eq([ "86.4", "86.4" ])
      expect(snapshot.room_attributes[:subtotal]).to eq(160)
      expect(snapshot.booking_attributes[:total_amount]).to eq("172.8".to_d)
    end
  end
end

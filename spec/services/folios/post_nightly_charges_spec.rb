# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::PostNightlyCharges do
  let(:business_date) { Date.current }
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, account: hotel.account) }
  let(:night_audit) { create(:night_audit, hotel: hotel, business_date: business_date, performed_by_user: user, status: "running") }

  it "posts one nightly accommodation and tax charge for an in-house booking" do
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date,
      check_out: business_date + 2.days,
      tax_lines: [ { "name" => "SST", "amount" => "20.00", "type" => "sst" } ])
    create(:booking_room, booking: booking, subtotal: 200.0)
    folio = create(:booking_folio, hotel: hotel, booking: booking)

    described_class.call(night_audit: night_audit, user: user)

    charges = folio.folio_transactions.charge.order(:category)
    expect(charges.count).to eq(2)
    expect(charges.find_by(category: "accommodation").amount).to eq(100.0)
    expect(charges.find_by(category: "tax").amount).to eq(10.0)
    expect(charges.map { |charge| charge.metadata["posting_source"] }.uniq).to eq([ "night_audit" ])
    expect(charges.map { |charge| charge.metadata["stay_date"] }.uniq).to eq([ business_date.iso8601 ])
  end

  it "posts accommodation and tax from financial snapshots" do
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date,
      check_out: business_date + 2.days,
      tax_posting_snapshot: {
        business_date.iso8601 => [ { "name" => "SST", "amount" => "20.00", "type" => "sst", "source" => "hotel_sst" } ]
      })
    create(:booking_room,
      booking: booking,
      subtotal: 999.0,
      nightly_rate_snapshot: {
        business_date.iso8601 => { "price" => "250.00", "source" => "room_rate" },
        (business_date + 1.day).iso8601 => { "price" => "300.00", "source" => "room_rate" }
      })
    folio = create(:booking_folio, hotel: hotel, booking: booking)

    described_class.call(night_audit: night_audit, user: user)

    expect(folio.folio_transactions.charge.find_by(category: "accommodation").amount).to eq(250.0)
    tax = folio.folio_transactions.charge.find_by(category: "tax")
    expect(tax.amount).to eq(20.0)
    expect(tax.metadata["tax_line"]["source"]).to eq("hotel_sst")
  end

  it "does not post a checkout-day charge" do
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date - 1.day,
      check_out: business_date)
    create(:booking_room, booking: booking, subtotal: 200.0)
    folio = create(:booking_folio, hotel: hotel, booking: booking)

    expect {
      described_class.call(night_audit: night_audit, user: user)
    }.not_to change { folio.folio_transactions.charge.count }
  end

  it "does not duplicate nightly charges" do
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date,
      check_out: business_date + 1.day,
      tax_lines: [ { "name" => "SST", "amount" => "10.00", "type" => "sst" } ])
    create(:booking_room, booking: booking, subtotal: 100.0)
    folio = create(:booking_folio, hotel: hotel, booking: booking)

    described_class.call(night_audit: night_audit, user: user)

    expect {
      described_class.call(night_audit: night_audit, user: user)
    }.not_to change { folio.folio_transactions.charge.count }
  end

  it "posts separate tax lines with the same tax type" do
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date,
      check_out: business_date + 1.day,
      tax_lines: [
        { "name" => "Local Tax", "amount" => "5.00", "type" => "local" },
        { "name" => "Local Tax", "amount" => "3.00", "type" => "local" }
      ])
    create(:booking_room, booking: booking, subtotal: 100.0)
    folio = create(:booking_folio, hotel: hotel, booking: booking)

    described_class.call(night_audit: night_audit, user: user)

    tax_charges = folio.folio_transactions.charge.where(category: "tax")
    expect(tax_charges.count).to eq(2)
    expect(tax_charges.sum(:amount)).to eq(8.0)
  end

  it "allocates rounding remainder to the final billable night" do
    final_night = business_date + 2.days
    final_night_audit = create(:night_audit, hotel: hotel, business_date: final_night, performed_by_user: user, status: "running")
    booking = create(:booking,
      hotel: hotel,
      status: "checked_in",
      check_in: business_date,
      check_out: business_date + 3.days)
    create(:booking_room, booking: booking, subtotal: 100.0)
    folio = create(:booking_folio, hotel: hotel, booking: booking)

    described_class.call(night_audit: final_night_audit, user: user)

    expect(folio.folio_transactions.charge.sole.amount).to eq(33.34)
  end
end

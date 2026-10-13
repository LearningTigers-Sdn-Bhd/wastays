# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExtraCharges::AutomaticEstimate do
  let(:hotel) { create(:hotel) }
  let(:check_in) { hotel.current_business_date + 10 }
  let(:check_out) { check_in + 3 }

  def estimate(adults: 2, children: 0)
    described_class.call(hotel: hotel, check_in: check_in, check_out: check_out, adults: adults, children: children)
  end

  def auto_charge(**attributes)
    create(:hotel_extra_charge, hotel: hotel, pricing_type: "fixed", allow_amount_override: false, auto_apply: true, **attributes)
  end

  it "charges a per-person fee once for the stay, for everyone in the room" do
    jetty_fee = auto_charge(rate_value: 10, charging_unit: "per_person")

    expect(estimate(adults: 2, children: 1)).to contain_exactly(have_attributes(extra_charge: jetty_fee, amount: 30.to_d))
  end

  it "leaves children out when the charge does not count them" do
    auto_charge(rate_value: 10, charging_unit: "per_person", charge_children: false)

    expect(estimate(adults: 2, children: 1).sole.amount).to eq(20.to_d)
  end

  it "charges a nightly fee for every night of the stay" do
    auto_charge(rate_value: 15, charging_unit: "per_room_night")

    expect(estimate.sole.amount).to eq(45.to_d)
  end

  it "adds the charge code's own taxes" do
    jetty_fee = auto_charge(rate_value: 10, charging_unit: "per_person")
    service_charge = create(:hotel_tax, hotel: hotel, name: "Service Charge", charge_type: "charge",
                                        rate_type: "percentage", amount: 10, enabled: true)
    jetty_fee.transaction_code.transaction_code_taxes.create!(hotel_tax: service_charge)

    expect(estimate.sole.amount).to eq(22.to_d)
  end

  it "ignores charges that are not auto-applied or are inactive" do
    auto_charge(rate_value: 10, charging_unit: "per_person", auto_apply: false)
    auto_charge(rate_value: 10, charging_unit: "per_person").transaction_code.update!(active: false)

    expect(estimate).to be_empty
  end
end

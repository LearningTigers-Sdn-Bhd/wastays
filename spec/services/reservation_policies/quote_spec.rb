# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReservationPolicies::Quote do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  # 3 nights, MYR 300 of pre-tax room revenue, plus tax on top of that.
  let(:booking) do
    create(:booking, hotel: hotel,
      check_in: Date.current, check_out: Date.current + 3.days,
      total_amount: 360.0, tourism_tax_amount: 30.0)
  end

  before do
    create(:booking_room, booking: booking, room_type: room_type, subtotal: 300.0)
    ReservationPolicies::EnsureDefaults.call(hotel)
  end

  def policy_for(policy_type) = hotel.hotel_reservation_policies.find_by(policy_type: policy_type)

  def quote(policy_type, business_date: nil)
    described_class.call(booking: booking, policy_type: policy_type, business_date: business_date)
  end

  it "returns no amount for a manual policy — staff name the figure" do
    result = quote("late_checkout")

    expect(result).to be_success
    expect(result.amount).to be_nil
    expect(result.label).to eq("Staff enters amount")
  end

  it "returns zero for an inactive policy" do
    result = quote("cancellation")

    expect(result).to be_success
    expect(result.amount).to eq(0)
    expect(result.label).to eq("Not charged")
  end

  it "bills whole nights at the pre-tax room rate" do
    policy_for("no_show").update!(pricing_type: "nights", rate_value: 2)

    expect(quote("no_show").amount).to eq(200.0)
  end

  it "bills a fixed amount as given" do
    policy_for("late_checkout").update!(pricing_type: "fixed", rate_value: 45)

    expect(quote("late_checkout").amount).to eq(45.0)
  end

  describe "percentage bases" do
    it "takes a share of the first night" do
      policy_for("late_checkout").update!(pricing_type: "percentage", rate_value: 50, percentage_basis: "first_night")

      expect(quote("late_checkout").amount).to eq(50.0)
    end

    it "takes a share of the whole stay" do
      policy_for("late_checkout").update!(pricing_type: "percentage", rate_value: 25, percentage_basis: "total_stay")

      expect(quote("late_checkout").amount).to eq(75.0)
    end

    it "takes a share of the nights still to come" do
      policy_for("late_checkout").update!(pricing_type: "percentage", rate_value: 100, percentage_basis: "remaining_nights")

      expect(quote("late_checkout", business_date: Date.current + 1.day).amount).to eq(200.0)
    end
  end

  # The charge posts pre-tax and PostAttachedTaxes adds ROOM's rules on top. A
  # quote that folded tax in would be taxed a second time on the way to the folio.
  it "quotes pre-tax amounts, never the tax-inclusive booking total" do
    policy_for("late_checkout").update!(pricing_type: "percentage", rate_value: 100, percentage_basis: "total_stay")

    expect(quote("late_checkout").amount).to eq(300.0)
    expect(quote("late_checkout").amount).not_to eq(booking.total_amount)
  end

  it "reports the stay length alongside the amount" do
    expect(quote("late_checkout").nights).to eq(3)
  end

  it "seeds the policies when a hotel has none yet" do
    hotel.hotel_reservation_policies.delete_all

    expect(quote("late_checkout")).to be_success
  end
end

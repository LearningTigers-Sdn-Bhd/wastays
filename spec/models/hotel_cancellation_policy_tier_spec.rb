# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelCancellationPolicyTier do
  let(:hotel) { create(:hotel) }
  let(:policy) { create(:hotel_reservation_policy, :charging_cancellation, hotel: hotel) }

  def tier(attributes = {})
    build(:hotel_cancellation_policy_tier, { hotel_reservation_policy: policy }.merge(attributes))
  end

  it "is valid as a free-cancellation band" do
    expect(tier(rate_value: 0)).to be_valid
  end

  # Zero is meaningful here in a way it is not on the parent policy: it is how a
  # hotel says "free cancellation up to this point".
  it "allows a zero rate but not a negative one" do
    expect(tier(rate_value: 0)).to be_valid
    expect(tier(rate_value: -1)).not_to be_valid
  end

  it "has no manual pricing — a tier must compute its own amount" do
    expect(tier(pricing_type: "manual", rate_value: 10)).not_to be_valid
  end

  it "requires a basis for percentage pricing" do
    expect(tier(pricing_type: "percentage", rate_value: 50, percentage_basis: nil)).not_to be_valid
  end

  it "caps a percentage at 100" do
    expect(tier(pricing_type: "percentage", percentage_basis: "total_stay", rate_value: 101)).not_to be_valid
  end

  it "requires whole nights" do
    expect(tier(pricing_type: "nights", percentage_basis: nil, rate_value: 1.5)).not_to be_valid
    expect(tier(pricing_type: "nights", percentage_basis: nil, rate_value: 1)).to be_valid
  end

  it "rejects a negative days threshold" do
    expect(tier(days_before_arrival: -1)).not_to be_valid
  end

  it "allows only one tier per days threshold" do
    create(:hotel_cancellation_policy_tier, hotel_reservation_policy: policy, days_before_arrival: 7)

    expect(tier(days_before_arrival: 7)).not_to be_valid
  end

  it "refuses to hang off a non-cancellation policy" do
    late_checkout = create(:hotel_reservation_policy, hotel: hotel, policy_type: "late_checkout")

    record = tier(hotel_reservation_policy: late_checkout)

    expect(record).not_to be_valid
    expect(record.errors[:hotel_reservation_policy]).to include("must be a cancellation policy")
  end

  it "is guarded by the database as well as the model" do
    record = tier(pricing_type: "percentage", percentage_basis: "total_stay", rate_value: 50)
    record.save!

    expect {
      record.update_column(:rate_value, 150)
    }.to raise_error(ActiveRecord::StatementInvalid, /percentage_maximum/)
  end

  describe "#label" do
    it "reads as plain language" do
      expect(tier(days_before_arrival: 14, rate_value: 0).label)
        .to eq("14+ days before arrival: No charge")
      expect(tier(days_before_arrival: 7, pricing_type: "percentage", percentage_basis: "total_stay", rate_value: 50).label)
        .to eq("7+ days before arrival: keep 50.00% of total stay")
      expect(tier(days_before_arrival: 0, pricing_type: "nights", percentage_basis: nil, rate_value: 1).label)
        .to eq("Less than 1 day before arrival: keep 1 night")
    end
  end
end

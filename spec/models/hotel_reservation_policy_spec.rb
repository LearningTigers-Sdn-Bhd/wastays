# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelReservationPolicy do
  let(:hotel) { create(:hotel) }

  def policy(attributes = {})
    build(:hotel_reservation_policy, { hotel: hotel }.merge(attributes))
  end

  it "is valid with the seeded manual shape" do
    expect(policy).to be_valid
  end

  describe "policy type" do
    it "rejects an unknown type" do
      expect(policy(policy_type: "walk_out")).not_to be_valid
    end

    it "allows only one policy of each type per hotel" do
      create(:hotel_reservation_policy, hotel: hotel, policy_type: "late_checkout")

      duplicate = policy(policy_type: "late_checkout")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:policy_type]).to include("has already been taken")
    end
  end

  describe "pricing" do
    it "rejects an unknown pricing type" do
      expect(policy(pricing_type: "whatever")).not_to be_valid
    end

    it "requires no rate for a manual policy" do
      expect(policy(pricing_type: "manual", rate_value: 50)).not_to be_valid
    end

    it "requires a positive rate when priced" do
      expect(policy(pricing_type: "fixed", rate_value: 0)).not_to be_valid
      expect(policy(pricing_type: "fixed", rate_value: 50)).to be_valid
    end

    it "requires a basis for percentage pricing" do
      expect(policy(pricing_type: "percentage", rate_value: 50, percentage_basis: nil)).not_to be_valid
      expect(policy(pricing_type: "percentage", rate_value: 50, percentage_basis: "total_stay")).to be_valid
    end

    it "caps a percentage at 100" do
      expect(policy(pricing_type: "percentage", rate_value: 101, percentage_basis: "total_stay")).not_to be_valid
    end

    it "requires whole nights" do
      expect(policy(pricing_type: "nights", rate_value: 1.5)).not_to be_valid
      expect(policy(pricing_type: "nights", rate_value: 2)).to be_valid
    end
  end

  # A no-show fee posts alongside the booking's per-night tax snapshot. Anything
  # other than whole nights would leave the fee and its tax out of step.
  describe "no-show" do
    it "must charge whole nights" do
      expect(policy(policy_type: "no_show", pricing_type: "fixed", rate_value: 80)).not_to be_valid
      expect(policy(policy_type: "no_show", pricing_type: "nights", rate_value: 1)).to be_valid
    end

    it "is rejected by the database constraint too" do
      record = policy(policy_type: "no_show", pricing_type: "nights", rate_value: 1)
      record.save!

      expect {
        record.update_column(:pricing_type, "fixed")
      }.to raise_error(ActiveRecord::StatementInvalid, /no_show_nights_only/)
    end
  end

  describe "refund terms" do
    it "allows them on a cancellation policy" do
      expect(policy(policy_type: "cancellation", refund_processing_days: 7, refund_method: "bank_transfer")).to be_valid
    end

    it "rejects them on any other policy" do
      expect(policy(policy_type: "late_checkout", refund_processing_days: 7)).not_to be_valid
    end

    it "rejects an out-of-range processing window" do
      expect(policy(policy_type: "cancellation", refund_processing_days: 400)).not_to be_valid
    end

    it "rejects an unknown refund method" do
      expect(policy(policy_type: "cancellation", refund_method: "cheque")).not_to be_valid
    end
  end

  it "rejects a transaction code from another hotel" do
    other = create(:hotel)
    Financials::EnsureDefaultTransactionCodes.call(other)

    record = policy(transaction_code: other.transaction_codes.find_by(system_key: "late_checkout_revenue"))

    expect(record).not_to be_valid
    expect(record.errors[:transaction_code]).to include("must belong to the same hotel")
  end

  describe "#pricing_label" do
    it "reads as plain language" do
      expect(policy(active: false).pricing_label).to eq("Not charged")
      expect(policy(pricing_type: "manual").pricing_label).to eq("Staff enters amount")
      expect(policy(policy_type: "no_show", pricing_type: "nights", rate_value: 1).pricing_label)
        .to eq("1 night at room rate")
      expect(policy(policy_type: "no_show", pricing_type: "nights", rate_value: 2).pricing_label)
        .to eq("2 nights at room rate")
      expect(policy(pricing_type: "percentage", rate_value: 50, percentage_basis: "first_night").pricing_label)
        .to eq("50.00% of first night")
    end
  end
end

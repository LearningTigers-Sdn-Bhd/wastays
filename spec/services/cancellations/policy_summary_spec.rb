# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cancellations::PolicySummary do
  let(:hotel) { create(:hotel) }

  def cancellation_policy_with(tiers, **attrs)
    policy = create(:hotel_reservation_policy, :charging_cancellation, hotel: hotel, **attrs)
    tiers.each_with_index do |tier, index|
      create(:hotel_cancellation_policy_tier, hotel_reservation_policy: policy, position: index + 1, **tier)
    end
    policy.reload
  end

  describe ".snapshot_for" do
    it "carries the tiers and the description together, most generous band first" do
      cancellation_policy_with(
        [
          { days_before_arrival: 0, pricing_type: "percentage", percentage_basis: "total_stay", rate_value: 100 },
          { days_before_arrival: 14, pricing_type: "percentage", percentage_basis: "total_stay", rate_value: 0 }
        ],
        description: "Non-refundable during Hari Raya."
      )

      snapshot = described_class.snapshot_for(hotel)

      expect(snapshot["tiers"].map { |tier| tier["days_before_arrival"] }).to eq([ 14, 0 ])
      expect(snapshot["tiers"].first).to include("window" => "14+ days before arrival", "charge" => "No charge")
      expect(snapshot["description"]).to eq("Non-refundable during Hari Raya.")
      expect(snapshot["refund_processing_days"]).to eq(7)
    end

    it "is empty when the hotel has no cancellation policy" do
      expect(described_class.snapshot_for(hotel)).to eq({})
    end

    it "is empty while the policy is inactive, since nothing is charged" do
      create(:hotel_reservation_policy, :cancellation, hotel: hotel)

      expect(described_class.snapshot_for(hotel)).to eq({})
    end
  end

  describe ".call" do
    it "renders rows, refund terms and description from a stored snapshot" do
      cancellation_policy_with(
        [ { days_before_arrival: 7, pricing_type: "percentage", percentage_basis: "total_stay", rate_value: 50 } ],
        description: "Groups follow 30-day terms."
      )

      summary = described_class.call(snapshot_data: described_class.snapshot_for(hotel))

      expect(summary.rows.map(&:window)).to eq([ "7+ days before arrival" ])
      expect(summary.rows.map(&:charge)).to eq([ "keep 50.00% of total stay" ])
      expect(summary.refund_note).to eq("Refunds are issued to the original payment method within 7 working days.")
      expect(summary.description).to eq("Groups follow 30-day terms.")
      expect(summary).to be_structured
    end

    it "falls back to the legacy prose when there is no structured payload" do
      summary = described_class.call(snapshot_data: {}, legacy_text: "Free cancellation 48 hours before check-in.")

      expect(summary.rows).to be_empty
      expect(summary).not_to be_structured
      expect(summary.to_text).to eq("Free cancellation 48 hours before check-in.")
    end

    it "prefers the structured payload over prose, so the two can never be shown together" do
      cancellation_policy_with([ { days_before_arrival: 0, pricing_type: "percentage", percentage_basis: "total_stay", rate_value: 100 } ])

      summary = described_class.call(snapshot_data: described_class.snapshot_for(hotel), legacy_text: "Old prose")

      expect(summary.to_text).not_to include("Old prose")
      expect(summary.to_text).to include("Less than 1 day before arrival: keep 100.00% of total stay")
    end

    it "is blank when there is neither structure nor prose" do
      expect(described_class.call(snapshot_data: nil)).to be_empty
    end
  end

  describe ".for_hotel" do
    it "falls back to the property policy prose while no structured policy is active" do
      create(:property_policy, hotel: hotel, cancellation_policy: "No refund after check-in")

      expect(described_class.for_hotel(hotel).to_text).to eq("No refund after check-in")
    end
  end

  describe ".for_record" do
    it "reads the booking's own snapshot rather than the hotel's current policy" do
      booking = create(:booking, hotel: hotel, cancellation_policy_snapshot_data: {
        "tiers" => [ { "days_before_arrival" => 3, "window" => "3+ days before arrival", "charge" => "No charge" } ]
      })

      expect(described_class.for_record(booking).rows.map(&:charge)).to eq([ "No charge" ])
    end

    it "falls back to the legacy text column for rows booked before the policy was structured" do
      booking = create(:booking, hotel: hotel, cancellation_policy_snapshot: "Free cancellation")

      expect(described_class.for_record(booking).to_text).to eq("Free cancellation")
    end
  end

  describe "#to_line" do
    it "flattens the table for chat surfaces that cannot hold one" do
      cancellation_policy_with(
        [
          { days_before_arrival: 0, pricing_type: "percentage", percentage_basis: "total_stay", rate_value: 100 },
          { days_before_arrival: 7, pricing_type: "percentage", percentage_basis: "total_stay", rate_value: 0 }
        ]
      )

      line = described_class.for_hotel(hotel).to_line

      expect(line).to eq(
        "7+ days before arrival: No charge; Less than 1 day before arrival: keep 100.00% of total stay " \
        "Refunds are issued to the original payment method within 7 working days."
      )
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReservationPolicies::Save do
  let(:hotel) { create(:hotel) }

  before { ReservationPolicies::EnsureDefaults.call(hotel) }

  def policy_for(policy_type) = hotel.hotel_reservation_policies.find_by(policy_type: policy_type)

  it "turns a policy off" do
    result = described_class.call(policy: policy_for("late_checkout"), attributes: { active: "0" })

    expect(result).to be_success
    expect(result.policy).not_to be_active
  end

  it "switches a policy to a fixed amount" do
    result = described_class.call(
      policy: policy_for("late_checkout"),
      attributes: { active: "1", pricing_type: "fixed", rate_value: "45", allow_amount_override: "1" }
    )

    expect(result).to be_success
    expect(result.policy.rate_value).to eq(45)
  end

  it "clears the rate when a policy goes back to manual" do
    policy = policy_for("late_checkout")
    described_class.call(policy: policy, attributes: { active: "1", pricing_type: "fixed", rate_value: "45" })

    result = described_class.call(policy: policy, attributes: { active: "1", pricing_type: "manual" })

    expect(result).to be_success
    expect(result.policy.rate_value).to be_nil
  end

  it "drops a stale percentage basis when leaving percentage pricing" do
    policy = policy_for("late_checkout")
    described_class.call(policy: policy, attributes: { active: "1", pricing_type: "percentage", rate_value: "50", percentage_basis: "total_stay" })

    result = described_class.call(policy: policy, attributes: { active: "1", pricing_type: "fixed", rate_value: "20" })

    expect(result).to be_success
    expect(result.policy.percentage_basis).to be_nil
  end

  it "reports why a policy could not be saved" do
    result = described_class.call(
      policy: policy_for("late_checkout"),
      attributes: { active: "1", pricing_type: "percentage", rate_value: "150", percentage_basis: "total_stay" }
    )

    expect(result).not_to be_success
    expect(result.error).to include("100 or less")
  end

  # The sheet disables every control beneath the gate switch when a policy is
  # switched off, and disabled inputs are not submitted. Turning a policy off
  # therefore posts `active` and nothing else.
  describe "turning a policy off from the sheet" do
    it "switches no-show off without complaining about the rate it still has" do
      result = described_class.call(policy: policy_for("no_show"), attributes: { active: "0" })

      expect(result).to be_success
      expect(result.policy).not_to be_active
      expect(result.policy.rate_value).to eq(1)
    end

    it "keeps the guest note" do
      policy = policy_for("late_checkout")
      described_class.call(policy: policy, attributes: { active: "1", description: "Waived for repeat guests." })

      described_class.call(policy: policy, attributes: { active: "0" })

      expect(policy.reload.description).to eq("Waived for repeat guests.")
    end

    it "keeps a configured amount and basis" do
      policy = policy_for("late_checkout")
      described_class.call(policy: policy, attributes: {
        active: "1", pricing_type: "percentage", rate_value: "50", percentage_basis: "first_night"
      })

      described_class.call(policy: policy, attributes: { active: "0" })

      expect(policy.reload.rate_value).to eq(50)
      expect(policy.percentage_basis).to eq("first_night")
    end

    it "keeps cancellation refund terms" do
      policy = policy_for("cancellation")
      described_class.call(policy: policy, attributes: {
        active: "1", refund_processing_days: "7", refund_method: "bank_transfer"
      })

      described_class.call(policy: policy, attributes: { active: "0" })

      expect(policy.reload.refund_processing_days).to eq(7)
      expect(policy.refund_method).to eq("bank_transfer")
    end
  end

  it "refuses to make a no-show policy anything but whole nights" do
    result = described_class.call(
      policy: policy_for("no_show"),
      attributes: { active: "1", pricing_type: "fixed", rate_value: "80" }
    )

    expect(result).not_to be_success
    expect(result.error).to include("whole nights")
  end

  describe "cancellation" do
    let(:policy) { policy_for("cancellation") }

    it "stores refund terms and tiers together" do
      result = described_class.call(policy: policy, attributes: {
        active: "1", refund_processing_days: "7", refund_method: "original_payment_method",
        cancellation_tiers_attributes: {
          "0" => { days_before_arrival: "14", pricing_type: "percentage", rate_value: "0", percentage_basis: "total_stay" },
          "1" => { days_before_arrival: "0", pricing_type: "nights", rate_value: "1" }
        }
      })

      expect(result).to be_success
      expect(result.policy.refund_processing_days).to eq(7)
      expect(result.policy.cancellation_tiers.map(&:days_before_arrival)).to eq([ 0, 14 ])
    end

    it "clears a basis on a tier that is not a percentage" do
      result = described_class.call(policy: policy, attributes: {
        active: "1",
        cancellation_tiers_attributes: {
          "0" => { days_before_arrival: "0", pricing_type: "nights", rate_value: "1", percentage_basis: "total_stay" }
        }
      })

      expect(result).to be_success
      expect(result.policy.cancellation_tiers.sole.percentage_basis).to be_nil
    end

    it "ignores an empty tier row from the form" do
      result = described_class.call(policy: policy, attributes: {
        active: "1",
        cancellation_tiers_attributes: {
          "0" => { days_before_arrival: "7", pricing_type: "percentage", rate_value: "50", percentage_basis: "total_stay" },
          "1" => { days_before_arrival: "", rate_value: "" }
        }
      })

      expect(result).to be_success
      expect(result.policy.cancellation_tiers.count).to eq(1)
    end

    it "rolls the whole save back when one tier is invalid" do
      result = described_class.call(policy: policy, attributes: {
        active: "1",
        cancellation_tiers_attributes: {
          "0" => { days_before_arrival: "7", pricing_type: "percentage", rate_value: "50", percentage_basis: "total_stay" },
          "1" => { days_before_arrival: "0", pricing_type: "percentage", rate_value: "150", percentage_basis: "total_stay" }
        }
      })

      expect(result).not_to be_success
      expect(policy.reload.cancellation_tiers).to be_empty
      expect(policy).not_to be_active
    end
  end
end

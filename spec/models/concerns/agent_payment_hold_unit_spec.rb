# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentPaymentHoldUnit do
  let(:hotel) { create(:hotel, status: "live") }

  # The stored column stays the canonical number every consumer reads; the unit
  # is only how the form talks about it.
  describe "writing" do
    it "stores days as hours" do
      hotel.update!(agent_payment_hold_amount: "3", agent_payment_hold_unit: "days")

      expect(hotel.reload.agent_payment_hold_hours).to eq(72)
    end

    it "stores hours as themselves" do
      hotel.update!(agent_payment_hold_amount: "36", agent_payment_hold_unit: "hours")

      expect(hotel.reload.agent_payment_hold_hours).to eq(36)
    end

    # assign_attributes applies the pair in hash order, so the result must not
    # depend on which field the form rendered first.
    it "converts the same way whichever field is assigned first" do
      unit_first = Hotel.new(agent_payment_hold_unit: "days", agent_payment_hold_amount: "2")
      amount_first = Hotel.new(agent_payment_hold_amount: "2", agent_payment_hold_unit: "days")

      unit_first.valid?
      amount_first.valid?

      expect(unit_first.agent_payment_hold_hours).to eq(48)
      expect(amount_first.agent_payment_hold_hours).to eq(48)
    end

    it "leaves the column alone on a save that never mentioned it" do
      hotel.update!(agent_payment_hold_amount: "5", agent_payment_hold_unit: "days")

      hotel.update!(name: "Renamed")

      expect(hotel.reload.agent_payment_hold_hours).to eq(120)
    end

    # Otherwise a form's earlier "3 days" would silently undo a script that
    # assigns the column directly on the same object.
    it "does not re-apply an earlier form value to a later direct assignment" do
      hotel.update!(agent_payment_hold_amount: "3", agent_payment_hold_unit: "days")

      hotel.update!(agent_payment_hold_hours: 12)

      expect(hotel.reload.agent_payment_hold_hours).to eq(12)
    end

    # Only where the column allows it: an agency's override is nullable, the
    # property default is not.
    it "clears a nullable override when the field is emptied" do
      relationship = create(:hotel_corporate_account, hotel: hotel, agent_payment_hold_hours: 48)

      relationship.update!(agent_payment_hold_amount: "", agent_payment_hold_unit: "hours")

      expect(relationship.reload.agent_payment_hold_hours).to be_nil
    end
  end

  describe "reading back" do
    it "reads a whole number of days as days" do
      hotel.update!(agent_payment_hold_hours: 72)

      expect(hotel.agent_payment_hold_unit).to eq("days")
      expect(hotel.agent_payment_hold_amount).to eq(3)
      expect(hotel.agent_payment_hold_label).to eq("3 days")
    end

    it "reads a value with no whole-day form as hours" do
      hotel.update!(agent_payment_hold_hours: 36)

      expect(hotel.agent_payment_hold_unit).to eq("hours")
      expect(hotel.agent_payment_hold_label).to eq("36 hours")
    end

    it "reads less than a day as hours" do
      hotel.update!(agent_payment_hold_hours: 6)

      expect(hotel.agent_payment_hold_label).to eq("6 hours")
    end

    it "says one day rather than one days" do
      hotel.update!(agent_payment_hold_hours: 24)

      expect(hotel.agent_payment_hold_label).to eq("1 day")
    end

    it "round-trips" do
      hotel.update!(agent_payment_hold_amount: "3", agent_payment_hold_unit: "days")
      reloaded = Hotel.find(hotel.id)

      expect([ reloaded.agent_payment_hold_amount, reloaded.agent_payment_hold_unit ]).to eq([ 3, "days" ])
    end

    it "has nothing to say for an unset override" do
      relationship = create(:hotel_corporate_account, hotel: hotel, agent_payment_hold_hours: nil)

      expect(relationship.agent_payment_hold_amount).to be_nil
      expect(relationship.agent_payment_hold_label).to be_nil
    end

    # A hold is far more often set in days than in hours, so an empty field
    # offers days rather than making the admin change the unit first.
    it "offers days for an unset override, and lists days first" do
      relationship = create(:hotel_corporate_account, hotel: hotel, agent_payment_hold_hours: nil)

      expect(relationship.agent_payment_hold_unit).to eq("days")
      expect(described_class::UNITS.first).to eq("days")
    end
  end

  # The validation lives on the stored column, but the field an admin can see
  # and fix is the amount.
  it "puts a rejected value's error on the field that was filled in" do
    hotel.assign_attributes(agent_payment_hold_amount: "0", agent_payment_hold_unit: "hours")

    expect(hotel).not_to be_valid
    expect(hotel.errors[:agent_payment_hold_amount]).to be_present
  end
end

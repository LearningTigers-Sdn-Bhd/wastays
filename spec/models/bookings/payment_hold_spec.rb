# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::PaymentHold do
  let(:hotel) { create(:hotel, status: "live", agent_payment_hold_hours: 48) }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent") }
  let(:now) { Time.zone.parse("2026-09-18 09:00") }

  def booking_for(relationship, check_in: now + 30.days)
    build(:booking, hotel: hotel, hotel_corporate_account: relationship,
                    check_in: check_in, check_out: check_in + 2.days)
  end

  describe ".due_at" do
    it "adds the hotel's default hold to the moment the booking was taken" do
      due = described_class.due_at(booking: booking_for(relationship), from: now)

      expect(due).to eq(now + 48.hours)
    end

    it "prefers the agency's own hold over the hotel default" do
      relationship.update!(agent_payment_hold_hours: 12)

      expect(described_class.due_at(booking: booking_for(relationship), from: now)).to eq(now + 12.hours)
    end

    # A 48-hour hold cannot run past the arrival it is holding.
    it "floors the deadline at arrival" do
      booking = booking_for(relationship, check_in: now + 6.hours)

      expect(described_class.due_at(booking: booking, from: now)).to eq(booking.check_in)
    end

    # Direct bill is invoiced after the stay by arrangement; releasing its rooms
    # up front would contradict that arrangement.
    it "gives a direct-bill account no deadline" do
      direct = create(:hotel_corporate_account, :direct_bill, hotel: hotel, account_type: "travel_agent")

      expect(described_class.due_at(booking: booking_for(direct), from: now)).to be_nil
    end

    it "gives a booking with no corporate account no deadline" do
      booking = build(:booking, hotel: hotel, check_in: now + 30.days, check_out: now + 32.days)

      expect(described_class.due_at(booking: booking, from: now)).to be_nil
    end
  end

  describe ".hours_for" do
    it "falls back to the hotel default, then to the module default" do
      expect(described_class.hours_for(relationship)).to eq(48)

      relationship.update!(agent_payment_hold_hours: 6)
      expect(described_class.hours_for(relationship)).to eq(6)
    end
  end

  describe ".floored_at_arrival?" do
    it "is true only when the hold would run past arrival" do
      expect(described_class.floored_at_arrival?(booking: booking_for(relationship, check_in: now + 6.hours), from: now)).to be(true)
      expect(described_class.floored_at_arrival?(booking: booking_for(relationship), from: now)).to be(false)
    end

    it "is false for an account that holds nothing" do
      direct = create(:hotel_corporate_account, :direct_bill, hotel: hotel, account_type: "travel_agent")

      expect(described_class.floored_at_arrival?(booking: booking_for(direct, check_in: now + 1.hour), from: now)).to be(false)
    end
  end
end

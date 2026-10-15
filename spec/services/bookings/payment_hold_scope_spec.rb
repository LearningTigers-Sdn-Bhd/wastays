# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::PaymentHoldScope do
  let(:hotel) { create(:hotel, status: "live") }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent") }

  # Status is moved through the lifecycle rather than assigned, which the model
  # refuses without a transition event.
  def checked_in_agent_booking(overrides = {})
    agent_booking(overrides).tap { |booking| booking.transition_status_to!("checked_in", event: "check_in") }
  end

  def agent_booking(overrides = {})
    create(:booking, {
      hotel: hotel,
      hotel_corporate_account: relationship,
      status: "confirmed",
      payment_status: "pending",
      payment_due_at: 4.hours.from_now
    }.merge(overrides))
  end

  # The money question, wider than .held by exactly one status. Keeping the two
  # apart is what lets an unpaid stay stay visible after arrival without putting
  # an occupied room back on sale.
  describe ".owing" do
    it "takes the same confirmed bookings .held does" do
      booking = agent_booking

      expect(described_class.owing).to include(booking)
    end

    it "keeps a booking whose guest has checked in unpaid" do
      booking = checked_in_agent_booking

      expect(described_class.owing).to include(booking)
      expect(described_class.held).not_to include(booking)
    end

    it "drops it once the money arrives" do
      expect(described_class.owing).not_to include(checked_in_agent_booking(payment_status: "captured"))
    end

    it "drops a cancelled booking as .held does" do
      expect(described_class.owing).not_to include(agent_booking(status: "cancelled"))
    end
  end

  describe ".held" do
    it "takes a confirmed, unpaid, corporate booking carrying a deadline" do
      booking = agent_booking

      expect(described_class.held).to include(booking)
    end

    # Each exclusion is a way the sweeper could otherwise cancel something it
    # must not, so they are asserted one at a time rather than as one example.
    it "leaves out a booking with no deadline" do
      expect(described_class.held).not_to include(agent_booking(payment_due_at: nil))
    end

    it "leaves out a booking that is already paid" do
      expect(described_class.held).not_to include(agent_booking(payment_status: "captured"))
    end

    it "leaves out a booking that is no longer confirmed" do
      expect(described_class.held).not_to include(agent_booking(status: "cancelled"))
    end

    # The rooms are occupied, so there is nothing to release. The debt does not
    # go away -- see .owing -- but the sweeper must not reach it.
    it "leaves out a booking whose guest has checked in" do
      expect(described_class.held).not_to include(checked_in_agent_booking)
    end

    it "leaves out a booking with no corporate account" do
      expect(described_class.held).not_to include(agent_booking(hotel_corporate_account: nil))
    end

    it "narrows an existing relation rather than replacing it" do
      other_hotel_booking = agent_booking
      create(:booking, hotel: hotel)

      expect(described_class.held(relation: Booking.where(id: other_hotel_booking.id))).to eq([ other_hotel_booking ])
    end
  end

  describe ".protected_by_submission?" do
    it "is true while a slip is waiting to be reviewed" do
      booking = agent_booking
      create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship, booking: booking, status: "pending")

      expect(described_class).to be_protected_by_submission(booking)
    end

    # Rejection restarts the clock, so a rejected slip must stop protecting the
    # booking or an agent could hold rooms indefinitely by sending bad slips.
    it "is false once that slip has been rejected" do
      booking = agent_booking
      create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship, booking: booking,
                                     status: "rejected", rejection_reason: "Amount did not match")

      expect(described_class).not_to be_protected_by_submission(booking)
    end

    it "is false when nothing has been sent" do
      expect(described_class).not_to be_protected_by_submission(agent_booking)
    end
  end
end

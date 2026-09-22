# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporatePortal::CancelAgentBooking do
  let(:hotel) { create(:hotel, status: "live") }
  let(:corporate_user) { create(:user, :corporate) }
  let(:relationship) do
    create(:hotel_corporate_account, hotel: hotel, corporate_account: corporate_user.account, account_type: "travel_agent")
  end

  def agent_booking(overrides = {})
    create(:booking, {
      hotel: hotel,
      hotel_corporate_account: relationship,
      status: "confirmed",
      payment_status: "pending",
      payment_due_at: 4.hours.from_now,
      check_in: 3.days.from_now,
      check_out: 5.days.from_now
    }.merge(overrides))
  end

  it "cancels the booking and keeps it as history rather than deleting it" do
    booking = agent_booking

    result = described_class.call(booking: booking, user: corporate_user)

    expect(result).to be_success
    expect(booking.reload.status).to eq("cancelled")
    expect(Booking.exists?(booking.id)).to be(true)
  end

  # Cancelling through Bookings::TransitionStatus is what returns the rooms to
  # sale and writes the audit trail. If this service ever stopped going through
  # it, inventory would silently stop tallying.
  it "records who cancelled it and where from" do
    booking = agent_booking

    described_class.call(booking: booking, user: corporate_user)

    log = BookingAuditLog.where(auditable: booking, action_type: "cancel").last
    expect(log.source).to eq(described_class::SOURCE)
    expect(log.user_id).to eq(corporate_user.id)
    expect(log.metadata["reason"]).to include(corporate_user.name)
  end

  it "releases the inventory the booking was holding" do
    booking = agent_booking
    room_type = create(:room_type, hotel: hotel)
    create(:booking_room, booking: booking, room_type: room_type)

    expect(Bookings::InventoryManager).to receive(:new).with(booking).and_call_original

    described_class.call(booking: booking, user: corporate_user)
  end

  # The sweeper must never look at a booking that is already gone.
  it "clears the payment deadline" do
    booking = agent_booking

    described_class.call(booking: booking, user: corporate_user)

    expect(booking.reload.payment_due_at).to be_nil
  end

  describe "a multi-room stay" do
    it "cancels every room in the group, not just the one asked for" do
      group = create(:group_booking, hotel: hotel)
      first = agent_booking(group_booking: group, group_position: 1)
      second = agent_booking(group_booking: group, group_position: 2)

      result = described_class.call(booking: first, user: corporate_user)

      expect(result.bookings.map(&:id)).to match_array([ first.id, second.id ])
      expect(second.reload.status).to eq("cancelled")
    end

    # The guard has to cover everything the service would cancel, not only the
    # row that was clicked.
    it "refuses the whole stay when one room in it has been paid for" do
      group = create(:group_booking, hotel: hotel)
      first = agent_booking(group_booking: group, group_position: 1)
      agent_booking(group_booking: group, group_position: 2, payment_status: "captured")

      result = described_class.call(booking: first, user: corporate_user)

      expect(result.error).to include("has been paid")
      expect(first.reload.status).to eq("confirmed")
    end

    it "does not reach another agency's booking that happens to share a group id" do
      group = create(:group_booking, hotel: hotel)
      mine = agent_booking(group_booking: group, group_position: 1)
      theirs = create(:booking, hotel: hotel, group_booking: group, group_position: 2,
                                hotel_corporate_account: create(:hotel_corporate_account, hotel: hotel))

      described_class.call(booking: mine, user: corporate_user)

      expect(theirs.reload.status).not_to eq("cancelled")
    end
  end

  describe "what it refuses" do
    it "refuses a booking that has already been cancelled" do
      result = described_class.call(booking: agent_booking(status: "cancelled"), user: corporate_user)

      expect(result).not_to be_success
      expect(result.error).to include("already been cancelled")
    end

    it "refuses a stay that has already begun" do
      booking = agent_booking(check_in: 1.hour.ago, check_out: 2.days.from_now)

      result = described_class.call(booking: booking, user: corporate_user)

      expect(result.error).to include("already started")
      expect(booking.reload.status).to eq("confirmed")
    end

    # Money already with the hotel is the hotel's to unwind. An agent-triggered
    # refund is not something this flow can decide.
    it "refuses a booking that is paid" do
      booking = agent_booking(payment_status: "captured", payment_due_at: nil)

      result = described_class.call(booking: booking, user: corporate_user)

      expect(result.error).to include("has been paid")
      expect(booking.reload.status).to eq("confirmed")
    end

    it "refuses while a transfer slip is waiting to be reviewed" do
      booking = agent_booking
      create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship,
                                     booking: booking, status: "pending")

      result = described_class.call(booking: booking, user: corporate_user)

      expect(result.error).to include("slip is with the hotel")
      expect(booking.reload.status).to eq("confirmed")
    end

    it "allows it again once that slip has been rejected" do
      booking = agent_booking
      create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship, booking: booking,
                                     status: "rejected", rejection_reason: "Amount did not match")

      expect(described_class.new(booking: booking, user: corporate_user)).to be_cancellable
    end
  end
end

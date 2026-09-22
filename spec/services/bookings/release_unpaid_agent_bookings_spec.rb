# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::ReleaseUnpaidAgentBookings do
  let(:hotel) { create(:hotel, status: "live") }
  let(:relationship) { create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent") }
  let(:now) { Time.current }

  def agent_booking(overrides = {})
    create(:booking, {
      hotel: hotel,
      hotel_corporate_account: relationship,
      status: "confirmed",
      payment_status: "pending",
      payment_due_at: now - 1.hour
    }.merge(overrides))
  end

  def submission_for(booking, status: "pending")
    create(:ar_payment_submission,
           hotel: hotel,
           hotel_corporate_account: relationship,
           booking: booking,
           status: status,
           rejection_reason: ("Slip did not match the amount" if status == "rejected"))
  end

  it "cancels a booking whose deadline has passed unpaid" do
    booking = agent_booking

    result = described_class.call(now: now)

    expect(result.released).to eq([ booking.id ])
    expect(booking.reload.status).to eq("cancelled")
  end

  # An automated cancellation in a money path that nobody can audit is not
  # acceptable, so the release has to leave a record naming itself and the
  # deadline it enforced.
  it "logs every release with its reason and source" do
    booking = agent_booking

    described_class.call(now: now)

    log = BookingAuditLog.where(auditable: booking, action_type: "cancel").last
    expect(log).to be_present
    expect(log.source).to eq(described_class::SOURCE)
    expect(log.metadata["reason"]).to include("Payment not received by")
  end

  it "returns the rooms to sale" do
    booking = agent_booking
    create(:booking_room, booking: booking, room_type: create(:room_type, hotel: hotel))

    expect { described_class.call(now: now) }.not_to raise_error
    expect(booking.reload.status).to eq("cancelled")
  end

  # The sweeper cancels; without this the agent finds out when a guest turns up.
  describe "telling people the rooms are gone" do
    let(:corporate_user) { create(:user, :corporate) }
    let(:relationship) do
      create(:hotel_corporate_account, hotel: hotel, corporate_account: corporate_user.account, account_type: "travel_agent")
    end

    it "writes to the agent who was holding them" do
      booking = agent_booking(corporate_booked_by: corporate_user)

      described_class.call(now: now)

      delivery = NotificationDelivery.find_by(booking: booking, notification_type: "agent_booking_released")
      expect(delivery).to have_attributes(status: "pending")
      expect(delivery.payload["recipient_email"]).to eq(corporate_user.email)
    end

    it "warns the desk on the bell, so a vanished reservation is not a surprise" do
      staff = create(:user)
      role = create(:role, account: hotel.account)
      role.permissions << Permission.find_or_create_by!(slug: "manage_ar_payments") { |p| p.name = "Manage AR Payments" }
      create(:user_hotel_access, user: staff, hotel: hotel, role: role)
      agent_booking

      described_class.call(now: now)

      expect(StaffNotification.where(recipient: staff, notification_type: "agent_booking_released")).to exist
    end

    it "does not tell the same agent twice when the sweep runs again" do
      booking = agent_booking(corporate_booked_by: corporate_user)
      described_class.call(now: now)

      described_class.call(now: now + 5.minutes)

      expect(NotificationDelivery.where(booking: booking, notification_type: "agent_booking_released").count).to eq(1)
    end

    # The rooms are already back on sale by this point. A mail server being down
    # must not undo that.
    it "still releases the rooms when notifying fails" do
      booking = agent_booking
      allow(Notifications::QueueAgentPaymentNotice).to receive(:call).and_raise(StandardError, "smtp down")

      result = described_class.call(now: now)

      expect(result.released).to eq([ booking.id ])
      expect(booking.reload.status).to eq("cancelled")
    end
  end

  describe "what it leaves alone" do
    it "leaves a booking whose deadline has not passed" do
      booking = agent_booking(payment_due_at: now + 1.hour)

      expect(described_class.call(now: now).released).to be_empty
      expect(booking.reload.status).to eq("confirmed")
    end

    it "leaves a booking that has been paid" do
      booking = agent_booking(payment_status: "captured")

      expect(described_class.call(now: now).released).to be_empty
      expect(booking.reload.status).to eq("confirmed")
    end

    it "leaves a booking with no deadline at all" do
      booking = agent_booking(payment_due_at: nil)

      expect(described_class.call(now: now).released).to be_empty
      expect(booking.reload.status).to eq("confirmed")
    end

    it "leaves a booking that is not an agent's" do
      booking = create(:booking, hotel: hotel, status: "confirmed",
                                 payment_status: "pending", payment_due_at: now - 1.hour)

      expect(described_class.call(now: now).released).to be_empty
      expect(booking.reload.status).to eq("confirmed")
    end

    it "leaves an already-cancelled booking alone" do
      booking = agent_booking
      booking.update_column(:status, "cancelled")

      expect(described_class.call(now: now).released).to be_empty
    end

    # The clock stops when the slip is uploaded, not when it is approved: an
    # agent should not lose rooms to the hotel's review queue.
    it "leaves a booking whose slip is still awaiting review" do
      booking = agent_booking
      submission_for(booking)

      expect(described_class.call(now: now).released).to be_empty
      expect(booking.reload.status).to eq("confirmed")
    end

    it "releases a booking whose slip was rejected" do
      booking = agent_booking
      submission_for(booking, status: "rejected")

      expect(described_class.call(now: now).released).to eq([ booking.id ])
    end

    it "ignores a pending submission belonging to a different booking" do
      protected_booking = agent_booking
      submission_for(protected_booking)
      exposed = agent_booking

      expect(described_class.call(now: now).released).to eq([ exposed.id ])
    end
  end

  # Running twice in the same minute must not cancel anything twice, and must
  # not raise on the second pass.
  it "is idempotent" do
    booking = agent_booking

    first = described_class.call(now: now)
    second = described_class.call(now: now)

    expect(first.released).to eq([ booking.id ])
    expect(second.released).to be_empty
    expect(BookingAuditLog.where(auditable: booking, action_type: "cancel").count).to eq(1)
  end

  it "can be scoped to one hotel" do
    mine = agent_booking
    other_hotel = create(:hotel, status: "live")
    other_relationship = create(:hotel_corporate_account, hotel: other_hotel, account_type: "travel_agent")
    theirs = create(:booking, hotel: other_hotel, hotel_corporate_account: other_relationship,
                              status: "confirmed", payment_status: "pending", payment_due_at: now - 1.hour)

    result = described_class.call(hotel: hotel, now: now)

    expect(result.released).to eq([ mine.id ])
    expect(theirs.reload.status).to eq("confirmed")
  end

  it "records a booking it could not cancel as failed rather than raising" do
    booking = agent_booking
    allow(Bookings::TransitionStatus).to receive(:new).and_raise(StandardError, "boom")

    result = described_class.call(now: now)

    expect(result.failed).to eq([ booking.id ])
    expect(booking.reload.status).to eq("confirmed")
  end
end

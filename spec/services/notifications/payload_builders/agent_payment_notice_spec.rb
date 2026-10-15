# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::PayloadBuilders::AgentPaymentNotice do
  let(:hotel) { create(:hotel, status: "live") }
  let(:corporate_user) { create(:user, :corporate) }
  let(:relationship) do
    create(:hotel_corporate_account, hotel: hotel, corporate_account: corporate_user.account, account_type: "travel_agent")
  end
  let(:booking) do
    create(:booking, hotel: hotel, hotel_corporate_account: relationship, corporate_booked_by: corporate_user,
                     status: "confirmed", payment_status: "pending", payment_due_at: 6.hours.from_now)
  end

  def payload(extra: {})
    described_class.new(
      booking: booking,
      notification_type: "agent_payment_reminder",
      trigger_event: "agent_payment_deadline_approaching",
      extra: extra
    ).call
  end

  # Frozen, because "6 hours left" is floored: a few microseconds of test setup
  # otherwise tips it to five.
  it "states the stay, the money and the deadline", frozen_time: :business_day do
    expect(payload).to include(
      notification_type: "agent_payment_reminder",
      booking_id: booking.id,
      reservation_number: booking.formatted_reservation_number,
      hotel_name: hotel.name,
      currency: booking.currency,
      recipient_email: corporate_user.email
    )
    expect(payload[:payment_due_label]).to be_present
    expect(payload[:time_left_label]).to eq("6 hours left")
  end

  # A reminder that only says "log in" wastes the time it is warning about.
  it "deep-links to the submission form for this booking" do
    expect(payload[:pay_url]).to include("booking_id=#{booking.id}")
  end

  it "carries the caller's extras alongside" do
    expect(payload(extra: { reminder_offset_hours: 24 })).to include(reminder_offset_hours: 24)
  end

  # The payload is the record of what the agent was told. A deadline that moves
  # afterwards must not rewrite it, so every value is copied in rather than
  # looked up at send time.
  it "keeps the deadline it was built with when the booking's later changes" do
    built = payload
    booking.update!(payment_due_at: 3.days.from_now)

    expect(built[:payment_due_at]).not_to eq(booking.reload.payment_due_at.iso8601)
  end
end

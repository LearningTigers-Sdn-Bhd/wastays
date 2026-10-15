# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::AgentPaymentReminderScheduler do
  let(:hotel) { create(:hotel, status: "live") }
  let(:corporate_user) { create(:user, :corporate) }
  let(:relationship) do
    create(:hotel_corporate_account, hotel: hotel, corporate_account: corporate_user.account, account_type: "travel_agent")
  end
  let(:now) { Time.current }

  before do
    create(:notification_config, hotel: hotel, notification_type: "agent_payment_reminder",
                                 enabled: true, channels: [ "email" ], settings: { "offsets_hours" => [ 24, 4 ] })
  end

  def agent_booking(due_in:, overrides: {})
    create(:booking, {
      hotel: hotel,
      hotel_corporate_account: relationship,
      corporate_booked_by: corporate_user,
      status: "confirmed",
      payment_status: "pending",
      check_in: 10.days.from_now,
      check_out: 12.days.from_now,
      payment_due_at: now + due_in
    }.merge(overrides))
  end

  def reminders_for(booking)
    NotificationDelivery.where(booking: booking, notification_type: "agent_payment_reminder")
  end

  it "says nothing while the deadline is further off than any offset" do
    booking = agent_booking(due_in: 3.days)

    described_class.call(now: now)

    expect(reminders_for(booking)).to be_empty
  end

  it "sends the 24-hour reminder once that window opens" do
    booking = agent_booking(due_in: 20.hours)

    result = described_class.call(now: now)

    expect(result.sent).to eq([ [ booking.id, 24 ] ])
    expect(reminders_for(booking).pluck(:status)).to eq([ "pending" ])
  end

  it "does not send the same offset twice on a later run" do
    booking = agent_booking(due_in: 20.hours)
    described_class.call(now: now)

    described_class.call(now: now + 1.hour)

    expect(reminders_for(booking).where(status: "pending").count).to eq(1)
  end

  it "sends the nearer reminder as its own window opens" do
    booking = agent_booking(due_in: 20.hours)
    described_class.call(now: now)

    result = described_class.call(now: now + 17.hours)

    expect(result.sent).to eq([ [ booking.id, 4 ] ])
  end

  # A booking made inside the final window has passed both offsets at once.
  # Sending both would be two identical mails a second apart.
  describe "a booking made inside the last window" do
    it "sends only the nearest offset" do
      booking = agent_booking(due_in: 3.hours)

      result = described_class.call(now: now)

      expect(result.sent).to eq([ [ booking.id, 4 ] ])
      expect(reminders_for(booking).where(status: "pending").count).to eq(1)
    end

    it "records the offsets it passed over, so the row says why nothing went out" do
      booking = agent_booking(due_in: 3.hours)

      described_class.call(now: now)

      skipped = reminders_for(booking).where(status: "skipped")
      expect(skipped.count).to eq(1)
      expect(skipped.first.payload["reminder_offset_hours"]).to eq(24)
    end

    it "does not reconsider the passed-over offset on a later run" do
      booking = agent_booking(due_in: 3.hours)
      described_class.call(now: now)

      described_class.call(now: now + 1.hour)

      expect(reminders_for(booking).count).to eq(2)
    end

    # An offset already on file was sent earlier, not passed over now, so a
    # later run must not tally it again.
    it "counts an offset as passed over only on the run that passed it over" do
      agent_booking(due_in: 20.hours)
      described_class.call(now: now)

      result = described_class.call(now: now + 17.hours)

      expect(result.skipped).to be_empty
    end
  end

  # A rejection extends payment_due_at, and the agent needs warning again
  # against the new date -- with the old rows still on file.
  it "starts a fresh series when the deadline moves" do
    booking = agent_booking(due_in: 20.hours)
    described_class.call(now: now)

    booking.update!(payment_due_at: now + 40.hours)
    result = described_class.call(now: now + 20.hours)

    expect(result.sent).to eq([ [ booking.id, 24 ] ])
    expect(reminders_for(booking).where(status: "pending").count).to eq(2)
  end

  describe "what it leaves alone" do
    it "says nothing while a transfer slip is waiting to be reviewed" do
      booking = agent_booking(due_in: 3.hours)
      create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship,
                                     booking: booking, status: "pending")

      described_class.call(now: now)

      expect(reminders_for(booking)).to be_empty
    end

    # That booking belongs to the sweeper. A reminder arriving as the rooms are
    # released would be worse than silence.
    it "says nothing once the deadline has already passed" do
      booking = agent_booking(due_in: -1.hour)

      described_class.call(now: now)

      expect(reminders_for(booking)).to be_empty
    end

    it "says nothing for a hotel that has the reminder switched off" do
      NotificationConfig.find_by(hotel: hotel, notification_type: "agent_payment_reminder").update!(enabled: false)
      booking = agent_booking(due_in: 3.hours)

      described_class.call(now: now)

      expect(reminders_for(booking)).to be_empty
    end

    it "says nothing for a hotel that has never configured it" do
      NotificationConfig.where(hotel: hotel, notification_type: "agent_payment_reminder").destroy_all
      booking = agent_booking(due_in: 3.hours)

      described_class.call(now: now)

      expect(reminders_for(booking)).to be_empty
    end

    it "says nothing for a booking that is already paid" do
      booking = agent_booking(due_in: 3.hours, overrides: { payment_status: "captured" })

      described_class.call(now: now)

      expect(reminders_for(booking)).to be_empty
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

# The whole payment-hold story, end to end, the way it actually happens: an
# admin sets a hold, an agent sells a room against it, the reminder scheduler
# and the release sweeper run on their timers, and the booking ends up in one of
# four states.
#
# Written as one spec per outcome rather than one per service because the bugs
# in this feature are all in the seams -- a deadline the reminder quotes but the
# sweeper has already moved, a slip that stops one clock and not the other -- and
# those are invisible from inside either service.
#
# Time is travelled rather than waited for. The hold columns are integer hours
# under a "> 0" constraint, so a hold cannot be configured in seconds; the
# shortest real hold is one hour, and these run a three-hour hold at speed.
RSpec.describe "Agent payment hold lifecycle", type: :integration do
  include ActiveJob::TestHelper

  # Step 1: the admin's settings.
  let(:hold_hours) { 3 }
  let(:reminder_offsets) { [ 2, 1 ] }

  let(:hotel) { create(:hotel, status: "live", default_currency: "MYR", agent_payment_hold_hours: 48) }
  let(:agent_user) { create(:user, :corporate, email: "ops@sunsettravel.test") }

  # The agency's own hold overrides the property default, which is the setting
  # the sales team actually negotiates.
  let(:relationship) do
    create(:hotel_corporate_account,
           hotel: hotel,
           corporate_account: agent_user.account,
           account_type: "travel_agent",
           relationship_type: "standard",
           agent_payment_hold_hours: hold_hours)
  end

  let!(:reminder_config) do
    create(:notification_config,
           hotel: hotel,
           notification_type: "agent_payment_reminder",
           enabled: true,
           channels: %w[email],
           settings: { "offsets_hours" => reminder_offsets })
  end

  let!(:room_type) do
    Rooms::SaveSeedRoomType.call!(
      hotel: hotel,
      attributes: { name: "Deluxe", room_number_mode: "custom", quantity: 2, base_price: 250.0,
                    max_adults: 3, max_children: 2, room_numbers: %w[101 102] }
    )
  end

  let(:booked_at) { Time.zone.parse("2026-10-01 09:00") }
  let(:check_in) { booked_at.to_date + 14 }
  let(:check_out) { check_in + 2 }

  # Step 2: the agent sells a room from their dashboard, with guest details.
  def book!
    result = CorporatePortal::CreateAgentBooking.call(
      relationship: relationship,
      user: agent_user,
      params: {
        room_type_id: room_type.id,
        check_in: check_in.to_s,
        check_out: check_out.to_s,
        adults: 2,
        children: 0,
        rooms: 1,
        special_requests: "High floor, late arrival.",
        rooms_detail: { "0" => { guests: {
          "0" => { name: "Ada Lim", email: "ada@example.test", phone: "+60123456789" },
          "1" => { name: "Grace Tan" }
        } } }
      }
    )
    raise "booking failed: #{result.errors.to_sentence}" unless result.success?

    result.booking
  end

  def submit_slip!(booking, amount: booking.total_amount)
    create(:ar_payment_submission,
           hotel: hotel,
           hotel_corporate_account: relationship,
           booking: booking,
           submitted_by: agent_user,
           # A standard agent has no invoice to allocate against: the remittance
           # targets the booking itself, which is the whole point of the column.
           auto_invoice: nil,
           amount: amount,
           currency: booking.currency,
           status: "pending")
  end

  def sweep! = Bookings::ReleaseUnpaidAgentBookings.call(hotel: hotel)
  def remind! = Notifications::AgentPaymentReminderScheduler.call(hotel: hotel)

  def deliveries_for(booking, type)
    NotificationDelivery.where(booking: booking, notification_type: type).order(:id)
  end

  def mails_for(booking)
    perform_enqueued_jobs(only: Notifications::DeliverJob)
    ActionMailer::Base.deliveries.select { |mail| mail.to&.include?(agent_user.email) }
  end

  before { ActionMailer::Base.deliveries.clear }

  # ---------------------------------------------------------------- the setup

  describe "the booking an agent gets" do
    it "is confirmed, holds the room, and carries the agency's deadline" do
      travel_to(booked_at) do
        booking = book!

        expect(booking.status).to eq("confirmed")
        expect(booking.payment_status).to eq("pending")
        expect(booking.payment_due_at).to eq(booked_at + hold_hours.hours)
        expect(booking.source).to eq("travel_agent")
        expect(booking.hotel_corporate_account).to eq(relationship)
        expect(booking.corporate_booked_by).to eq(agent_user)
        expect(booking.corporate_booked_at).to eq(booked_at)
        expect(booking.guest_name).to eq("Ada Lim")
        expect(booking.booking_guests.map(&:name_snapshot)).to include("Grace Tan")
        expect(booking.special_requests).to eq("High floor, late arrival.")
      end
    end

    it "takes the agency's hold over the property default" do
      travel_to(booked_at) { expect(book!.payment_due_at).to eq(booked_at + 3.hours) }
    end
  end

  describe "the reminders before the deadline" do
    it "stays quiet until the first offset opens, then sends one mail per offset" do
      booking = travel_to(booked_at) { book! }

      travel_to(booked_at + 30.minutes) { remind! }
      expect(deliveries_for(booking, "agent_payment_reminder")).to be_empty

      travel_to(booked_at + 1.hour + 5.minutes) { remind! }
      travel_to(booked_at + 2.hours + 10.minutes) { remind! }

      sent = deliveries_for(booking, "agent_payment_reminder").where(status: "pending")
      expect(sent.map { |d| d.payload["reminder_offset_hours"] }).to eq([ 2, 1 ])
      expect(sent.map { |d| d.payload["recipient_email"] }.uniq).to eq([ agent_user.email ])
    end

    it "does not send the same offset twice however often the scheduler runs" do
      booking = travel_to(booked_at) { book! }

      3.times { travel_to(booked_at + 1.hour + 5.minutes) { remind! } }

      expect(deliveries_for(booking, "agent_payment_reminder").where(status: "pending").count).to eq(1)
    end

    # A booking taken with less time left than the widest offset has passed
    # several windows at once. Two identical mails a second apart would be worse
    # than one, so only the nearest is sent -- and the others still leave a row.
    it "collapses offsets that opened together into one mail and one skipped row" do
      booking = travel_to(booked_at) { book! }

      travel_to(booked_at + 2.hours + 10.minutes) { remind! }

      reminders = deliveries_for(booking, "agent_payment_reminder")
      expect(reminders.where(status: "pending").map { |d| d.payload["reminder_offset_hours"] }).to eq([ 1 ])
      expect(reminders.where(status: "skipped").map { |d| d.payload["reminder_offset_hours"] }).to eq([ 2 ])
    end

    it "actually delivers the reminder to the agent" do
      booking = travel_to(booked_at) { book! }
      travel_to(booked_at + 2.hours + 10.minutes) { remind! }

      expect(mails_for(booking).map(&:subject).join(" ")).to match(/payment|due|deadline/i)
      expect(deliveries_for(booking, "agent_payment_reminder").where(status: "sent")).to be_present
    end

    it "sends nothing when the hotel has the reminder switched off" do
      reminder_config.update!(enabled: false)
      booking = travel_to(booked_at) { book! }

      travel_to(booked_at + 2.hours + 10.minutes) { remind! }

      expect(deliveries_for(booking, "agent_payment_reminder")).to be_empty
    end
  end

  # ------------------------------------------------------------ scenario one

  describe "scenario 1: paid inside the window, hotel approves" do
    it "clears the deadline, keeps the room, and tells the agent" do
      booking = travel_to(booked_at) { book! }
      travel_to(booked_at + 2.hours + 10.minutes) { remind! }

      submission = travel_to(booked_at + 2.hours + 15.minutes) { submit_slip!(booking) }

      # The clock stops on upload, before anyone has looked at the slip.
      travel_to(booked_at + 3.hours + 5.minutes) do
        expect(sweep!.released).to be_empty
        expect(booking.reload.status).to eq("confirmed")
      end

      travel_to(booked_at + 4.hours) do
        result = ArPaymentSubmissions::Approve.call(
          submission: submission,
          ar_payment: create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: booking.total_amount),
          reviewed_by: create(:user)
        )
        expect(result).to be_success
      end

      expect(booking.reload.payment_due_at).to be_nil
      expect(booking.status).to eq("confirmed")
      expect(deliveries_for(booking, "agent_payment_approved")).to be_present

      # Both portals now read "Paid", because the presenter follows the deadline
      # rather than the column.
      expect(CorporatePortal::BookingPaymentPresenter.new(booking).state).to eq(:paid)

      # The money reaches the booking's own folio, not just the agency's AR
      # ledger -- so the desk settling this stay at checkout sees it paid too.
      expect(booking.payment_status).to eq("captured")
      expect(booking.booking_folios.sum { |folio| folio.total_payments.to_d }).to eq(booking.total_amount)
      expect(ArPayment.where(hotel_corporate_account: relationship).sum(:amount)).to eq(booking.total_amount)

      # And it is never picked up again, by either timer.
      travel_to(booked_at + 2.days) do
        expect(sweep!.released).to be_empty
        expect(remind!.sent).to be_empty
      end
      expect(booking.reload.status).to eq("confirmed")
    end
  end

  # ------------------------------------------------------------ scenario two

  describe "scenario 2: paid inside the window, hotel rejects, agent pays again" do
    it "restarts the clock with the review time added back and ends confirmed" do
      booking = travel_to(booked_at) { book! }
      original_due = booking.payment_due_at

      submission = travel_to(booked_at + 2.hours) { submit_slip!(booking, amount: 1.0) }

      travel_to(booked_at + 2.hours + 30.minutes) do
        result = ArPaymentSubmissions::Reject.call(
          submission: submission, reason: "The slip is for RM1, not the room total.", reviewed_by: create(:user)
        )
        expect(result).to be_success
      end

      # Half an hour of review time handed back.
      expect(booking.reload.payment_due_at).to eq(original_due + 30.minutes)
      rejection = deliveries_for(booking, "agent_payment_rejected").last
      expect(rejection.payload["rejection_reason"]).to include("not the room total")
      expect(rejection.payload["payment_due_at"]).to eq((original_due + 30.minutes).iso8601)

      # A fresh slip inside the extended window, approved.
      second = travel_to(booked_at + 3.hours) { submit_slip!(booking) }
      travel_to(booked_at + 3.hours + 10.minutes) do
        ArPaymentSubmissions::Approve.call(
          submission: second,
          ar_payment: create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: booking.total_amount),
          reviewed_by: create(:user)
        )
      end

      travel_to(booked_at + 1.day) { sweep! }
      expect(booking.reload.status).to eq("confirmed")
      expect(booking.payment_due_at).to be_nil
    end
  end

  # ---------------------------------------------------------- scenario three

  describe "scenario 3: paid inside the window, hotel rejects, agent does nothing" do
    it "releases the rooms once the extended deadline passes" do
      booking = travel_to(booked_at) { book! }
      submission = travel_to(booked_at + 2.hours) { submit_slip!(booking, amount: 1.0) }

      travel_to(booked_at + 2.hours + 30.minutes) do
        ArPaymentSubmissions::Reject.call(submission: submission, reason: "Wrong amount.", reviewed_by: create(:user))
      end

      # Still inside the extended window: nothing happens.
      travel_to(booked_at + 3.hours + 5.minutes) do
        expect(sweep!.released).to be_empty
        expect(booking.reload.status).to eq("confirmed")
      end

      travel_to(booked_at + 3.hours + 35.minutes) do
        expect(sweep!.released).to eq([ booking.id ])
      end

      expect(booking.reload.status).to eq("cancelled")
      expect(deliveries_for(booking, "agent_booking_released")).to be_present
    end
  end

  # ----------------------------------------------------------- scenario four

  describe "scenario 4: never paid" do
    it "warns, then cancels, logs the release, and puts the room back on sale" do
      booking = travel_to(booked_at) { book! }

      travel_to(booked_at + 1.hour + 5.minutes) { remind! }
      travel_to(booked_at + 2.hours + 10.minutes) { remind! }
      expect(deliveries_for(booking, "agent_payment_reminder").where(status: "pending").count).to eq(2)

      # A minute before, the room is still held.
      travel_to(booked_at + 2.hours + 59.minutes) do
        expect(sweep!.released).to be_empty
        expect(remind!.sent).to be_empty # past both offsets, already sent
      end

      travel_to(booked_at + 3.hours + 1.minute) do
        expect(sweep!.released).to eq([ booking.id ])
      end

      booking.reload
      expect(booking.status).to eq("cancelled")

      log = BookingAuditLog.where(auditable: booking, action_type: "cancel").last
      expect(log.source).to eq(Bookings::ReleaseUnpaidAgentBookings::SOURCE)
      expect(log.metadata["reason"]).to include("Payment not received by")

      released = deliveries_for(booking, "agent_booking_released").last
      expect(released.payload["recipient_email"]).to eq(agent_user.email)
      expect(mails_for(booking).map(&:subject).join(" ")).to match(/release|cancel/i)

      # The inventory is genuinely back: the agent can sell it again.
      travel_to(booked_at + 3.hours + 5.minutes) do
        search = CorporatePortal::AgentStaySearch.call(
          hotel: hotel, check_in: check_in.to_s, check_out: check_out.to_s, adults: 2, children: 0, rooms: 2
        )
        option = search.options.find { |o| o.room_type.id == room_type.id }
        expect(option).to be_available
      end
    end

    it "is idempotent -- a second sweep in the same minute changes nothing" do
      booking = travel_to(booked_at) { book! }

      travel_to(booked_at + 3.hours + 1.minute) do
        sweep!
        expect(sweep!.released).to be_empty
      end

      expect(BookingAuditLog.where(auditable: booking, action_type: "cancel").count).to eq(1)
    end
  end

  # --------------------------------------------------------------- the edges

  describe "the edges the four scenarios do not reach" do
    it "gives a direct-bill agency no deadline at all" do
      relationship.update!(relationship_type: "direct_bill")
      booking = travel_to(booked_at) { book! }

      expect(booking.payment_due_at).to be_nil
      travel_to(booked_at + 10.days) { expect(sweep!.released).to be_empty }
      expect(booking.reload.status).to eq("confirmed")
    end

    it "floors the deadline at arrival for a stay that starts inside the window" do
      tomorrow = booked_at + 20.hours
      booking = travel_to(booked_at) do
        allow_any_instance_of(Booking).to receive(:check_in).and_return(tomorrow)
        build(:booking, hotel: hotel, hotel_corporate_account: relationship)
      end

      expect(Bookings::PaymentHold.due_at(booking: booking, from: booked_at)).to eq(booked_at + 3.hours)

      relationship.update!(agent_payment_hold_hours: 48)
      expect(Bookings::PaymentHold.due_at(booking: booking, from: booked_at)).to eq(tomorrow)
      expect(Bookings::PaymentHold.floored_at_arrival?(booking: booking, from: booked_at)).to be(true)
    end

    it "never hands out a deadline in the past on a same-day sale" do
      arrival = booked_at - 1.hour
      booking = build(:booking, hotel: hotel, hotel_corporate_account: relationship)
      allow(booking).to receive(:check_in).and_return(arrival)

      due = Bookings::PaymentHold.due_at(booking: booking, from: booked_at)
      expect(due).to eq(booked_at + Bookings::PaymentHold::MINIMUM_HOLD)
      expect(Bookings::PaymentHold.booked_after_arrival?(booking: booking, from: booked_at)).to be(true)
    end

    it "leaves an in-house booking alone but still counts it as owing" do
      booking = travel_to(booked_at) { book! }
      booking.update_columns(status: "checked_in")

      travel_to(booked_at + 1.day) { expect(sweep!.released).to be_empty }
      expect(booking.reload.status).to eq("checked_in")
      expect(Bookings::PaymentHoldScope.owing).to include(booking)
      expect(Bookings::PaymentHoldScope.held).not_to include(booking)
    end

    it "does not chase or cancel a booking the agent already cancelled" do
      booking = travel_to(booked_at) { book! }
      booking.update_columns(status: "cancelled")

      travel_to(booked_at + 1.day) do
        expect(sweep!.released).to be_empty
        expect(remind!.sent).to be_empty
      end
    end

    # An agent sells two rooms as one group. Each is its own booking with its own
    # deadline, so the sweep takes them one at a time -- and the group record has
    # to end up agreeing with the rooms under it.
    it "releases every room of a multi-room agent booking" do
      result = travel_to(booked_at) do
        CorporatePortal::CreateAgentBooking.call(
          relationship: relationship, user: agent_user,
          params: { room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
                    adults: 2, children: 0, rooms: 2,
                    rooms_detail: { "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } },
                                    "1" => { guests: { "0" => { name: "Grace Tan", phone: "+60123456780" } } } } }
        )
      end
      expect(result.bookings.size).to eq(2)
      expect(result.bookings.map(&:payment_due_at).uniq.size).to eq(1)

      travel_to(booked_at + 3.hours + 1.minute) do
        expect(sweep!.released).to match_array(result.bookings.map(&:id))
      end

      expect(result.bookings.map { |b| b.reload.status }.uniq).to eq([ "cancelled" ])
      # The group is closed with its last room, so the desk's list does not go on
      # reading "active" for a stay nobody is holding rooms for.
      expect(result.group_booking&.reload&.status).to eq("cancelled")
    end

    it "leaves the group active while at least one room of it is still held" do
      result = travel_to(booked_at) do
        CorporatePortal::CreateAgentBooking.call(
          relationship: relationship, user: agent_user,
          params: { room_type_id: room_type.id, check_in: check_in.to_s, check_out: check_out.to_s,
                    adults: 2, children: 0, rooms: 2,
                    rooms_detail: { "0" => { guests: { "0" => { name: "Ada Lim", phone: "+60123456789" } } },
                                    "1" => { guests: { "0" => { name: "Grace Tan", phone: "+60123456780" } } } } }
        )
      end

      submit_slip!(result.bookings.last)

      travel_to(booked_at + 3.hours + 1.minute) { expect(sweep!.released).to eq([ result.bookings.first.id ]) }

      expect(result.bookings.first.reload.status).to eq("cancelled")
      expect(result.bookings.last.reload.status).to eq("confirmed")
      expect(result.group_booking&.reload&.status).to eq("active")
    end

    it "records a skipped delivery when the agency has nobody to write to" do
      booking = travel_to(booked_at) { book! }
      booking.update!(corporate_booked_by: nil)
      relationship.update!(contact_email: nil)
      allow_any_instance_of(HotelCorporateAccount).to receive(:effective_contact_email).and_return(nil)

      travel_to(booked_at + 3.hours + 1.minute) { sweep! }

      delivery = deliveries_for(booking, "agent_booking_released").last
      expect(delivery.status).to eq("skipped")
      expect(delivery.error_message).to include("no contact email")
    end
  end
end

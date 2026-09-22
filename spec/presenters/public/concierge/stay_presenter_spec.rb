require "rails_helper"

RSpec.describe Public::Concierge::StayPresenter do
  let(:hotel) { create(:hotel, status: "live") }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:booking) do
    create(:booking, hotel: hotel, status: "checked_in", guest_name: "Ahmad Zulkifli",
      check_in: Date.current, check_out: Date.current + 3.days)
  end
  let(:stay_access) { create(:concierge_stay_access, hotel: hotel, booking: booking) }

  subject(:presenter) { described_class.new(stay_access: stay_access) }

  def move_booking(status, event, **attributes)
    booking.status_transition_event = event
    booking.update!(status: status, **attributes)
  end

  it "greets by the first name" do
    expect(presenter.greeting_name).to eq("Ahmad")
  end

  it "falls back to Guest when the name is blank" do
    booking.update_columns(guest_name: " ")

    expect(described_class.new(stay_access: stay_access.reload).greeting_name).to eq("Guest")
  end

  it "counts the nights" do
    expect(presenter.nights).to eq(3)
  end

  it "says the room is not assigned yet" do
    expect(presenter.room_label).to eq("To be assigned")
  end

  it "lists the assigned rooms" do
    create(:booking_room, booking: booking, room_type: room_type, room_number: "1201")

    expect(described_class.new(stay_access: stay_access).room_label).to eq("1201")
  end

  describe "do not disturb" do
    let(:booking_room) { create(:booking_room, booking: booking, room_type: room_type, room_number: "1201") }

    def room_status(dnd:, on: hotel.current_business_date)
      booking_room
      create(:room_status, hotel: hotel, room_type: room_type, room_number: "1201",
        dnd: dnd, dnd_date: (dnd ? on : nil))
    end

    it "is off when no room is assigned" do
      expect(presenter.do_not_disturb_active?).to be false
    end

    it "is off when the room has no status row yet" do
      booking_room

      expect(described_class.new(stay_access: stay_access).do_not_disturb_active?).to be false
    end

    it "is on when the room is flagged for today" do
      room_status(dnd: true)

      expect(described_class.new(stay_access: stay_access).do_not_disturb_active?).to be true
    end

    # The flag lasts one business date. A guest who turned it on yesterday is
    # not still on it, and the switch must not say they are.
    it "is off when the flag is from an earlier business date" do
      room_status(dnd: true, on: hotel.current_business_date - 1.day)

      expect(described_class.new(stay_access: stay_access).do_not_disturb_active?).to be false
    end

    it "ignores a flag on another room of the same hotel" do
      booking_room
      create(:room_status, hotel: hotel, room_type: room_type, room_number: "1500",
        dnd: true, dnd_date: hotel.current_business_date)

      expect(described_class.new(stay_access: stay_access).do_not_disturb_active?).to be false
    end

    it "does not create the row it reads" do
      booking_room

      expect { described_class.new(stay_access: stay_access).do_not_disturb_active? }
        .not_to change(RoomStatus, :count)
    end
  end

  describe "what the page offers" do
    it "offers check-out while the guest is in house" do
      expect(presenter.can_request_check_out?).to be true
      expect(presenter.check_out_pending?).to be false
    end

    it "hides check-out once a request is open" do
      Concierge::SubmitCheckOutRequest.new(booking: booking).call

      expect(presenter.can_request_check_out?).to be false
      expect(presenter.check_out_pending?).to be true
    end

    it "offers do not disturb only with a room and a check-in" do
      expect(presenter.can_toggle_do_not_disturb?).to be false

      create(:booking_room, booking: booking, room_type: room_type, room_number: "1201")

      expect(described_class.new(stay_access: stay_access).can_toggle_do_not_disturb?).to be true
    end

    it "hides the invoice while the guest is in house" do
      expect(presenter.invoice_available?).to be false
    end

    it "offers the invoice after check-out" do
      move_booking("completed", "check_out", checked_out_at: Time.current)

      expect(described_class.new(stay_access: stay_access.reload).invoice_available?).to be true
    end

    it "offers a refund until one is open" do
      expect(presenter.can_request_refund?).to be true

      create(:refund_request, booking: booking, status: "pending", refund_amount: 100.0)

      expect(described_class.new(stay_access: stay_access).can_request_refund?).to be false
    end

    it "offers a refund again after staff rejects one" do
      create(:refund_request, booking: booking, status: "rejected", refund_amount: 100.0)

      expect(described_class.new(stay_access: stay_access).can_request_refund?).to be true
    end
  end

  it "names the grace period end when one was given" do
    ends_at = 7.days.from_now
    presenter = described_class.new(stay_access: stay_access, expires_at: ends_at)

    expect(presenter.grace_period_ends_at).to eq(ends_at)
  end
end

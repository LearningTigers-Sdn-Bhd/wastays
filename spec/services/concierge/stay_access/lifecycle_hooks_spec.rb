require "rails_helper"

# The two ends of the stay link: check-in creates and mails it, and a status
# change that ends the stay revokes it.
RSpec.describe "Concierge stay access lifecycle" do
  let(:hotel) { create(:hotel, status: "live") }
  let(:booking) do
    create(:booking, hotel: hotel, status: "checked_in", guest_email: "ahmad@example.com")
  end

  def move_booking(status, event, **attributes)
    booking.status_transition_event = event
    booking.update!(status: status, **attributes)
  end

  describe "revocation on a status change" do
    before { Concierge::StayAccess::Ensure.new(booking: booking).call }

    it "keeps the link when the booking checks out" do
      move_booking("completed", "check_out", checked_out_at: Time.current)

      expect(booking.concierge_stay_accesses.live).to be_present
    end

    it "revokes the link when the grace period has already passed" do
      move_booking("completed", "check_out", checked_out_at: 8.days.ago)

      expect(booking.concierge_stay_accesses.live).to be_empty
    end

    it "revokes the link when the booking is voided" do
      move_booking("voided", "void")

      expect(booking.concierge_stay_accesses.live).to be_empty
    end

    it "revokes the link when staff undoes the check-in" do
      move_booking("confirmed", "undo_check_in", checked_in_at: nil)

      expect(booking.concierge_stay_accesses.live).to be_empty
    end

    it "keeps the link while the booking is due out" do
      move_booking("due_out_detected", "detect_due_out")

      expect(booking.concierge_stay_accesses.live).to be_present
    end
  end

  describe "check-in through Bookings::TransitionStatus" do
    let(:room_type) { create(:room_type, hotel: hotel) }
    let(:confirmed) do
      create(:booking, hotel: hotel, status: "confirmed", guest_email: "siti@example.com")
    end

    it "creates the record and queues the mail" do
      create(:booking_room, booking: confirmed, room_type: room_type, room_number: "1201")

      expect {
        Bookings::TransitionStatus.new(booking: confirmed, status: "checked_in").call
      }.to have_enqueued_mail(GuestMailer, :stay_link)

      expect(confirmed.reload.concierge_stay_accesses.live).to be_present
    end
  end
end

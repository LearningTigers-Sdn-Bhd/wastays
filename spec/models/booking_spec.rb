require 'rails_helper'

RSpec.describe Booking, type: :model do
  describe "constants" do
    it "includes checked_in in STATUSES" do
      expect(Booking::STATUSES).to include('checked_in')
    end

    it "includes no_show in STATUSES" do
      expect(Booking::STATUSES).to include('no_show')
    end

    it "includes voided in STATUSES" do
      expect(Booking::STATUSES).to include('voided')
    end
  end

  describe "scopes" do
    let(:hotel) { create(:hotel) }
    let!(:confirmed_booking) { create(:booking, hotel: hotel, status: 'confirmed') }
    let!(:checked_in_booking) { create(:booking, hotel: hotel, status: 'checked_in') }
    let!(:completed_booking) { create(:booking, hotel: hotel, status: 'completed') }
    let!(:no_show_booking) { create(:booking, hotel: hotel, status: 'no_show') }
    let!(:cancelled_booking) { create(:booking, hotel: hotel, status: 'cancelled') }

    describe ".active" do
      it "includes confirmed and checked_in bookings" do
        expect(Booking.active).to include(confirmed_booking, checked_in_booking)
        expect(Booking.active).not_to include(completed_booking, no_show_booking, cancelled_booking)
      end
    end

    describe ".revenue_generating" do
      it "includes confirmed, checked_in, completed, and no-show bookings" do
        expect(Booking.revenue_generating).to include(confirmed_booking, checked_in_booking, completed_booking, no_show_booking)
        expect(Booking.revenue_generating).not_to include(cancelled_booking)
      end
    end
  end

  describe "#checked_in?" do
    let(:booking) { build(:booking) }

    it "returns true if status is checked_in" do
      booking.status = 'checked_in'
      expect(booking.checked_in?).to be true
    end

    it "returns false if status is not checked_in" do
      booking.status = 'confirmed'
      expect(booking.checked_in?).to be false
    end
  end

  describe "#checked_out?" do
    let(:booking) { build(:booking) }

    it "returns true if status is completed" do
      booking.status = 'completed'
      expect(booking.checked_out?).to be true
    end

    it "returns false if status is not completed" do
      booking.status = 'checked_in'
      expect(booking.checked_out?).to be false
    end
  end

  describe "#guest_registration_card_number_display" do
    it "assigns a guest registration number when booking is created" do
      booking = create(:booking, guest_registration_number: nil)

      expect(booking.guest_registration_number).to be_present
    end

    it "shows pending only for legacy bookings without a guest registration number" do
      booking = build(:booking, guest_registration_number: nil)

      expect(booking.guest_registration_card_number_display).to eq("Pending check-in")
    end

    it "shows formatted guest registration number when present" do
      hotel = build(:hotel, hotel_prefix: "ABC")
      booking = build(:booking, hotel: hotel, guest_registration_number: 1)

      expect(booking.guest_registration_card_number_display).to eq("ABC-20000001")
    end
  end

  describe "#group_booking?" do
    let(:booking) { create(:booking) }
    let(:room_type) { create(:room_type, hotel: booking.hotel) }

    it "is false without a group booking" do
      expect(booking).not_to be_group_booking
    end

    it "is false for a standalone booking with one room" do
      create(:booking_room, booking: booking, room_type: room_type)

      expect(booking.reload).not_to be_group_booking
    end

    it "is true for each child of a multi-room group booking" do
      group = create(:group_booking, hotel: booking.hotel)
      booking.update!(group_booking: group, group_position: 1)
      sibling = create(:booking, hotel: booking.hotel, group_booking: group, group_position: 2)
      create(:booking_room, booking: booking, room_type: room_type)
      create(:booking_room, booking: sibling, room_type: room_type)

      expect(booking.reload).to be_group_booking
      expect(sibling.reload).to be_group_booking
    end
  end

  describe "status lifecycle" do
    def expect_transition(from:, to:, event:)
      booking = create(
        :booking,
        status: from,
        no_show_review_business_date: (Date.current if from == "review_no_show")
      )
      attributes = { no_show_review_business_date: Date.current } if to == "review_no_show"

      expect {
        booking.transition_status_to!(to, event: event, attributes: attributes || {})
      }.to change { booking.reload.status }.from(from).to(to)
    end

    it "allows valid lifecycle transitions" do
      expect_transition(from: "pending", to: "confirmed", event: "confirm")
      expect_transition(from: "pending", to: "cancelled", event: "cancel")
      expect_transition(from: "confirmed", to: "checked_in", event: "check_in")
      expect_transition(from: "confirmed", to: "cancelled", event: "cancel")
      expect_transition(from: "confirmed", to: "review_no_show", event: "review_no_show")
      expect_transition(from: "review_no_show", to: "no_show", event: "mark_no_show")
      expect_transition(from: "review_no_show", to: "no_show", event: "auto_mark_no_show")
      expect_transition(from: "review_no_show", to: "checked_in", event: "backdated_check_in")
      expect_transition(from: "review_no_show", to: "cancelled", event: "cancel")
      expect_transition(from: "confirmed", to: "overbooked", event: "mark_overbooked")
      expect_transition(from: "overbooked", to: "confirmed", event: "resolve_overbooking")
      expect_transition(from: "overbooked", to: "cancelled", event: "cancel")
      expect_transition(from: "checked_in", to: "completed", event: "check_out")
      expect_transition(from: "checked_in", to: "review_due_out", event: "detect_late_checkout")
      expect_transition(from: "review_due_out", to: "checked_in", event: "resolve_late_checkout")
      expect_transition(from: "review_due_out", to: "checkout_required", event: "reject_late_checkout")
      expect_transition(from: "checkout_required", to: "completed", event: "check_out")
      expect_transition(from: "no_show", to: "checked_in", event: "reinstate")
      (Booking::STATUSES - %w[voided]).each do |status|
        expect_transition(from: status, to: "voided", event: "void")
      end
    end

    it "rejects direct persisted status updates without an event" do
      booking = create(:booking, status: "confirmed")

      expect(booking.update(status: "checked_in")).to be(false)
      expect(booking.errors[:status]).to include("status transition event is required")
      expect(booking.reload.status).to eq("confirmed")
    end

    it "rejects checkout-required bookings returning to confirmed" do
      booking = create(:booking, status: "checkout_required")
      booking.status_transition_event = "confirm"

      expect(booking.update(status: "confirmed")).to be(false)
      expect(booking.errors[:status]).to include("cannot transition from checkout_required to confirmed with event confirm")
      expect(booking.reload.status).to eq("checkout_required")
    end

    it "rejects status changes with the wrong event" do
      booking = create(:booking, status: "confirmed")
      booking.status_transition_event = "check_out"

      expect(booking.update(status: "completed")).to be(false)
      expect(booking.errors[:status]).to include("cannot transition from confirmed to completed with event check_out")
      expect(booking.reload.status).to eq("confirmed")
    end

    it "treats cancelled as a hard terminal status" do
      booking = create(:booking, status: "cancelled")
      booking.status_transition_event = "confirm"

      expect(booking.update(status: "confirmed")).to be(false)
      expect(booking.errors[:status]).to include("cancelled is a terminal status")
      expect(booking.reload.status).to eq("cancelled")
    end

    it "treats completed as a hard terminal status" do
      booking = create(:booking, status: "completed")
      booking.status_transition_event = "check_in"

      expect(booking.update(status: "checked_in")).to be(false)
      expect(booking.errors[:status]).to include("completed is a terminal status")
      expect(booking.reload.status).to eq("completed")
    end

    it "treats voided as a hard terminal status" do
      booking = create(:booking, status: "voided")
      booking.status_transition_event = "confirm"

      expect(booking.update(status: "confirmed")).to be(false)
      expect(booking.errors[:status]).to include("voided is a terminal status")
      expect(booking.reload.status).to eq("voided")
    end

    it "allows setting the initial status on create" do
      booking = create(:booking, status: "completed")

      expect(booking.reload.status).to eq("completed")
    end

    it "requires a business date while pending no-show review" do
      booking = build(:booking, status: "review_no_show", no_show_review_business_date: nil)

      expect(booking).not_to be_valid
      expect(booking.errors[:no_show_review_business_date]).to include("can't be blank")
    end
  end

  describe "after_create_commit callbacks" do
    let(:hotel)     { create(:hotel) }
    let(:room_type) { create(:room_type, hotel: hotel) }

    def booking_with_room(status:)
      booking = create(:booking, hotel: hotel, status: status,
                       tourism_tax_applied: false, tourism_tax_amount: 0.0)
      create(:booking_room, booking: booking, room_type: room_type,
             subtotal: 200.0, room_type_snapshot: { "name" => room_type.name })
      booking
    end

    context "when created with confirmed status" do
      it "enqueues SendReceiptEmailJob" do
        expect {
          booking_with_room(status: "confirmed")
        }.to have_enqueued_job(SendReceiptEmailJob)
      end
    end

    context "when created with pending status" do
      it "does not enqueue SendReceiptEmailJob" do
        expect {
          booking_with_room(status: "pending")
        }.not_to have_enqueued_job(SendReceiptEmailJob)
      end
    end
  end

  describe "after_create_commit - WhatsApp receipt" do
    let(:hotel)     { create(:hotel) }
    let(:room_type) { create(:room_type, hotel: hotel) }

    def booking_with_room(status:)
      booking = create(:booking, hotel: hotel, status: status,
                       tourism_tax_applied: false, tourism_tax_amount: 0.0)
      create(:booking_room, booking: booking, room_type: room_type,
             subtotal: 200.0, room_type_snapshot: { "name" => room_type.name })
      booking
    end

    it "enqueues SendWhatsappReceiptJob when status is confirmed" do
      expect {
        booking_with_room(status: "confirmed")
      }.to have_enqueued_job(SendWhatsappReceiptJob)
    end

    it "does not enqueue SendWhatsappReceiptJob when status is pending" do
      expect {
        booking_with_room(status: "pending")
      }.not_to have_enqueued_job(SendWhatsappReceiptJob)
    end
  end

  describe "CTA/CTD validations" do
    let(:hotel) { create(:hotel) }
    let(:room_type) { create(:room_type, hotel: hotel) }
    let(:check_in) { Date.current }
    let(:check_out) { check_in + 2.days }

    it "allows booking when there are no restrictions" do
      booking = build(:booking, hotel: hotel, check_in: check_in, check_out: check_out)
      booking.booking_rooms.build(room_type: room_type, subtotal: 100.0)

      expect(booking).to be_valid
    end

    it "blocks booking when check-in date is CTA" do
      RoomRate.create!(room_type: room_type, date: check_in, price: 100, currency: "MYR", rate_plan: room_type.rate_plans.first, closed_to_arrival: true)

      booking = build(:booking, hotel: hotel, check_in: check_in, check_out: check_out)
      booking.booking_rooms.build(room_type: room_type, subtotal: 100.0)

      expect(booking).not_to be_valid
      expect(booking.errors[:check_in].first).to include("closed to arrival")
    end

    it "blocks booking when check-out date is CTD" do
      RoomRate.create!(room_type: room_type, date: check_out, price: 100, currency: "MYR", rate_plan: room_type.rate_plans.first, closed_to_departure: true)

      booking = build(:booking, hotel: hotel, check_in: check_in, check_out: check_out)
      booking.booking_rooms.build(room_type: room_type, subtotal: 100.0)

      expect(booking).not_to be_valid
      expect(booking.errors[:check_out].first).to include("closed to departure")
    end

    it "does not affect existing bookings when restrictions are added later" do
      booking = create(:booking, hotel: hotel, check_in: check_in, check_out: check_out)
      create(:booking_room, booking: booking, room_type: room_type)

      RoomRate.create!(room_type: room_type, date: check_in, price: 100, currency: "MYR", rate_plan: room_type.rate_plans.first, closed_to_arrival: true)

      expect(booking.reload).to be_valid
    end
  end
end

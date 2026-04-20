require 'rails_helper'

RSpec.describe Booking, type: :model do
  describe "constants" do
    it "includes checked_in in STATUSES" do
      expect(Booking::STATUSES).to include('checked_in')
    end
  end

  describe "scopes" do
    let(:hotel) { create(:hotel) }
    let!(:confirmed_booking) { create(:booking, hotel: hotel, status: 'confirmed') }
    let!(:checked_in_booking) { create(:booking, hotel: hotel, status: 'checked_in') }
    let!(:completed_booking) { create(:booking, hotel: hotel, status: 'completed') }
    let!(:cancelled_booking) { create(:booking, hotel: hotel, status: 'cancelled') }

    describe ".active" do
      it "includes confirmed and checked_in bookings" do
        expect(Booking.active).to include(confirmed_booking, checked_in_booking)
        expect(Booking.active).not_to include(completed_booking, cancelled_booking)
      end
    end

    describe ".revenue_generating" do
      it "includes confirmed, checked_in, and completed bookings" do
        expect(Booking.revenue_generating).to include(confirmed_booking, checked_in_booking, completed_booking)
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
      it "enqueues SendInvoiceEmailJob" do
        expect {
          booking_with_room(status: "confirmed")
        }.to have_enqueued_job(SendInvoiceEmailJob)
      end
    end

    context "when created with pending status" do
      it "does not enqueue SendInvoiceEmailJob" do
        expect {
          booking_with_room(status: "pending")
        }.not_to have_enqueued_job(SendInvoiceEmailJob)
      end
    end
  end
end

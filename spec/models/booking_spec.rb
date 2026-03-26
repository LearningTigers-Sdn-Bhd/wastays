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
end
